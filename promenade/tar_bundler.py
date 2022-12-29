import hashlib
import io
import tarfile
import time

from promenade import logging

__all__ = ['TarBundler']

LOG = logging.getLogger(__name__)


class TarBundler:
    def __init__(self):
        self._tar_blob = io.BytesIO()
        self._tf = tarfile.open(fileobj=self._tar_blob, mode='w|gz')

    def add(self, *, path, data, mode, islink=False):
        if path.startswith('/'):
            path = path[1:]

        tar_info = tarfile.TarInfo(name=path)
        if isinstance(data, str):
            data_bytes = data.encode('utf-8')
        else:
            data_bytes = data
        tar_info.size = len(data_bytes)
        tar_info.mode = mode
        tar_info.mtime = int(time.time())

        if tar_info.size > 0:
            # Ignore bandit false positive: B303:blacklist
            # This is a basic checksum for debugging not a secure hash.
            checksum = hashlib.new('md5', usedforsecurity=False)
            checksum.update(data_bytes)
            LOG.debug(  # nosec
                'Adding file path=%s size=%s md5=%s', path, tar_info.size,
                checksum.hexdigest())
        else:
            LOG.warning('Zero length file added to path=%s', path)

        if islink:
            tar_info.type = tarfile.SYMTYPE
            tar_info.linkname = data
            self._tf.addfile(tar_info)
        else:
            self._tf.addfile(tar_info, io.BytesIO(data_bytes))

    def as_blob(self):
        self._tf.close()
        return self._tar_blob.getvalue()
