LIB_DIR=$(realpath $(dirname $BASH_SOURCE))

source $LIB_DIR/config.sh
source $LIB_DIR/const.sh
source $LIB_DIR/etcd.sh
source $LIB_DIR/kube.sh
source $LIB_DIR/log.sh
source $LIB_DIR/promenade.sh
source $LIB_DIR/registry.sh
source $LIB_DIR/ssh.sh
source $LIB_DIR/validate.sh
source $LIB_DIR/virsh.sh

if [ "x${PROMENADE_DEBUG}" = "x1" ]; then
    set -x
fi
