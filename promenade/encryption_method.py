from . import exceptions, logging
import abc
import os
# Ignore bandit false positive: B404:blacklist
# The purpose of this module is to safely encapsulate calls via fork.
import subprocess  # nosec
import tempfile

__all__ = ['EncryptionMethod']

LOG = logging.getLogger(__name__)


class EncryptionMethod(metaclass=abc.ABCMeta):

    @abc.abstractmethod
    def encrypt(self, data):
        pass

    @abc.abstractmethod
    def get_decrypt_setup_command(self):
        pass

    @abc.abstractmethod
    def get_decrypt_command(self):
        pass

    @abc.abstractmethod
    def get_decrypt_teardown_command(self):
        pass

    @staticmethod
    def from_config(config):
        LOG.debug('Building EncryptionMethod from: %s', config)
        if config:
            # NOTE(mark-burnett): Relying on the schema to ensure valid
            # configuration.
            name = list(config.keys())[0]
            kwargs = config[name]
            if name == 'gpg':
                return GPGEncryptionMethod(**kwargs)
            else:
                raise NotImplementedError('Unknown Encryption method')
        else:
            return NullEncryptionMethod()

    def notify_user(self, message):
        print('=== BEGIN NOTICE ===')
        print(message)
        print('=== END NOTICE ===')


class NullEncryptionMethod(EncryptionMethod):

    def encrypt(self, data):
        LOG.debug('Performing NOOP encryption')
        return data

    def get_decrypt_setup_command(self):
        return ''

    def get_decrypt_command(self):
        return 'cat'

    def get_decrypt_teardown_command(self):
        return ''


class GPGEncryptionMethod(EncryptionMethod):
    ENCRYPTION_KEY_ENV_NAME = 'PROMENADE_ENCRYPTION_KEY'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._gpg_version = _detect_gpg_version()

    def encrypt(self, data):
        key = self._get_key()
        return self._encrypt_data(key, data)

    def get_decrypt_setup_command(self):
        return '''
        export DECRYPTION_KEY=${PROMENADE_ENCRYPTION_KEY:-"NONE"}
        if [[ ${PROMENADE_ENCRYPTION_KEY} = "NONE" ]]; then
            read -p "Script decryption key: " -s DECRYPTION_KEY
        fi
        '''

    def get_decrypt_command(self):
        return ('/usr/bin/gpg --verbose --decrypt --batch '
                '--passphrase "${DECRYPTION_KEY}"')

    def get_decrypt_teardown_command(self):
        return 'unset DECRYPTION_KEY'

    def _get_key(self):
        key = os.environ.get(self.ENCRYPTION_KEY_ENV_NAME)
        if key is None:
            key = _generate_key()
            self.notify_user('Copy this decryption key for use during script '
                             'execution:\n%s' % key)
        else:
            LOG.info('Using encryption key from %s',
                     self.ENCRYPTION_KEY_ENV_NAME)

        return key

    def _encrypt_data(self, key, data):
        with tempfile.TemporaryDirectory() as tmp:
            # Ignore bandit false positive:
            #   B603:subprocess_without_shell_equals_true
            # Here user input is allowed to be arbitrary, as it's simply input
            # to the specified encryption algorithm.  Regardless, we only put a
            # tarball here.
            p = subprocess.Popen(  # nosec
                [
                    '/usr/bin/gpg',
                    '--verbose',
                    '--symmetric',
                    '--homedir',
                    tmp,
                    '--passphrase',
                    key,
                ] + self._gpg_encrypt_options(),
                cwd=tmp,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)

            try:
                out, err = p.communicate(data, timeout=120)
            except subprocess.TimeoutExpired:
                p.kill()
                out, err = p.communicate()

            if p.returncode != 0:
                LOG.error('Got errors from gpg encrypt: %s', err)
                raise exceptions.EncryptionException(description=str(err))

            return out

    def _gpg_encrypt_options(self):
        options = {
            1: [],
            2: ['--pinentry-mode', 'loopback'],
        }
        return options[self._gpg_version[0]]


DETECTION_PREFIX = 'gpg (GnuPG) '


def _detect_gpg_version():
    with tempfile.TemporaryDirectory() as tmp:
        # Ignore bandit false positive:
        #   B603:subprocess_without_shell_equals_true
        # This method takes no input and simply queries the version of gpg.
        output = subprocess.check_output(  # nosec
            [
                '/usr/bin/gpg',
                '--version',
            ], cwd=tmp)
        lines = output.decode('utf-8').strip().splitlines()
        if lines:
            version = lines[0][len(DETECTION_PREFIX):]
            LOG.debug('Found GPG version %s', version)
            return tuple(map(int, version.split('.')[:2]))
        else:
            raise exceptions.GPGDetectionException()


def _generate_key():
    with tempfile.TemporaryDirectory() as tmp:
        # Ignore bandit false positive:
        #   B603:subprocess_without_shell_equals_true
        # This method takes no input and generates random output.
        result = subprocess.run(  # nosec
            ['/usr/bin/openssl', 'rand', '-hex', '48'],
            check=True,
            env={
                'RANDFILE': tmp,
            },
            stdout=subprocess.PIPE,
        )

    return result.stdout.decode().strip()
