# Copyright 2017 The Promenade Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function validate_environment {
    local ERRORS=

    if [ "x${NODE_HOSTNAME}" = "x" ]; then
        echo Error: NODE_HOSTNAME not defined, but required.
        ERRORS=1
    fi

    if ! docker info; then
        cat <<EOS
Error: Unable to run `docker info`.  You must mount /var/run/docker.sock when
you run this container, since it is used to launch containers on the host:
    docker run -v /var/run/docker.sock:/var/run/docker.sock ...
EOS
        ERRORS=1
    fi

    if [ ! -d /target/etc/systemd/system ]; then
        cat <<EOS
Error: It appears that the host's root filesystem is not mounted at /target.
Make sure it is mounted:
    docker run -v /:/target ...
EOS
        ERRORS=1
    fi

    if [ "x$ERRORS" != "x" ]; then
        exit 1
    fi
}

function install_assets {
    mkdir /target/etc/kubernetes
    cp -R ./assets/* /target/etc/kubernetes
}

function install_cni {
    mkdir -p /opt/cni/bin
    tar xf cni.tgz -C /opt/cni/bin/
}

function install_kubelet {
    cp ./kubelet /target/usr/local/bin/kubelet

    cat ./kubelet.service.template | envsubst > /target/etc/systemd/system/kubelet.service
    chown root:root /target/etc/systemd/system/kubelet.service
    chmod 644 /target/etc/systemd/system/kubelet.service

    chroot --userspec root:root /target /bin/bash < ./scripts/start-kubelet.sh
}
