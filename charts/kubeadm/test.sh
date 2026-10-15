#!/bin/bash

#set -euo pipefail

# number of failed checks, the script fails if there are any
FAILURES=0

_rootfs_mock() {
  local test_bin="${ROOTFS}/bin"
  mkdir -p "${test_bin}"

  # sudo
  cat << 'EOF' > "${test_bin}/sudo"
#!/usr/bin/env bash
echo "[MOCK sudo] $@" >> "${ROOTFS}/mock_calls.log"
EOF

  # systemctl
  cat << 'EOF' > "${test_bin}/systemctl"
#!/usr/bin/env bash
echo "[MOCK systemctl] systemctl $@" >> "${ROOTFS}/mock_calls.log"
exit 0
EOF

  # kubeadm
  cat << 'EOF' > "${test_bin}/kubeadm"
#!/usr/bin/env bash
echo "[MOCK kubeadm] kubeadm $@" >> "${ROOTFS}/mock_calls.log"

# if called with init/join, simulate activity
# if [[ "$1" == "init" ]]; then
#   mkdir -p "${ROOTFS}/etc/kubernetes/pki"
#   touch "${ROOTFS}/etc/kubernetes/admin.conf"
# fi
exit 0
EOF

chmod +x "${test_bin}"/*
}

assert_logged() {
  local log_file="${ROOTFS}/mock_calls.log"
  local pattern="$1"
  local msg="$2"

  if grep -E -q "${pattern}" "${log_file}" 2>/dev/null; then
    echo "  ✅ [OK] ${msg}"
  else
    echo "  ❌ [FAIL] Missing execution: ${msg} (pattern: '${pattern}')" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

assert_before() {
  local log_file="${ROOTFS}/mock_calls.log"
  local first_pattern="$1"
  local second_pattern="$2"
  local msg="$3"

  local line_a line_b
  line_a=$(grep -n -E "${first_pattern}" "${log_file}" | head -n1 | cut -d: -f1)
  line_b=$(grep -n -E "${second_pattern}" "${log_file}" | head -n1 | cut -d: -f1)

  if [[ -n "$line_a" && -n "$line_b" && "$line_a" -lt "$line_b" ]]; then
    echo "  ✅ [OK] Order verified: ${msg}"
  else
    echo "  ❌ [FAIL] Order violation: expected '${first_pattern}' line($line_a) before '${second_pattern}' line($line_b)" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}


RUN_COUNTER=0
run_bootstrap() {
  RUN_COUNTER=$((RUN_COUNTER + 1))
  local run_rootfs="kubeadm-test-rootfs-${RUN_COUNTER}"
  echo "[Run #${RUN_COUNTER}] Running with arg: $@"

  local script="script"
  local nodename="$1"
  shift 1

  local overrides=""
  local extra_helm_args=""
  local script_args=()

  # Parsing named args
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--values)
        overrides="$overrides -f $2"
        shift 2
        ;;
      --set)
        extra_helm_args="$extra_helm_args --set $2"
        shift 2
        ;;
      --) # everything after -- goes to `bash -s`
        shift
        script_args=("$@")
        break
        ;;
      *)
        echo "Unknown option: $1" >&2
        FAILURES=$((FAILURES + 1))
        return 1
        ;;
    esac
  done

  # env vars settings (can be redefined from outside)
  local yq="${YQ:-yq}"
  local helm="${HELM:-helm}"

  local postfix=""
  if [ -n "$nodename" ]; then
    postfix="-${nodename}"
  fi

  local target_secret="kubeadm-service-bootstrap${postfix}"
  local bootstrap_code

  #set new rootfs
  rm -rf "${run_rootfs}" || true
  mkdir -p "${run_rootfs}/tmp"
  export ROOTFS=${run_rootfs}

# 1. rended helm, save output to bootstrap_code
  echo "running helm template kubeadm ${overrides} \
    --set manifests.secret_bootstrap=true \
    ${extra_helm_args}
    "
  bootstrap_code=$("${helm}" template kubeadm \
    ${overrides} \
    --set manifests.secret_bootstrap=true \
    ${extra_helm_args} | \
  "${yq}" eval ". | select(.kind == \"Secret\" and .metadata.name == \"${target_secret}\") | .data[\"${script}\"] | @base64d" 2>/dev/null)

  # 2. check that yq returned non empty and non "null" data
  if [[ -z "${bootstrap_code}" || "${bootstrap_code}" == "null" ]]; then
    echo "Error: Script '${script}' in Secret '${target_secret}' was not found in rendered Helm output." >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  # 2.1. check that the script can be taken with sed + base64 (see README.md):
  # with bootstrap.nodename the only Secret is rendered, without the node
  # suffix. Both tools read the same output: embedded tarballs have the
  # render time as mtime, so two renders are never identical.
  local nodename_args=""
  if [ -n "$nodename" ]; then
    nodename_args="--set bootstrap.nodename=${nodename}"
  fi
  local rendered yq_code sed_code
  rendered=$("${helm}" template kubeadm \
    ${overrides} \
    --set manifests.secret_bootstrap=true \
    ${extra_helm_args} \
    ${nodename_args})
  yq_code=$(echo "${rendered}" | \
    "${yq}" eval ". | select(.kind == \"Secret\" and .metadata.name == \"kubeadm-service-bootstrap\") | .data[\"${script}\"] | @base64d" 2>/dev/null)
  sed_code=$(echo "${rendered}" | sed -n 's/^ *script: *\(.*\)/\1/p' | base64 -d)

  if [[ -n "${sed_code}" && "${sed_code}" == "${yq_code}" ]]; then
    echo "  ✅ [OK] Script taken with sed + base64 matches the one taken with yq"
  else
    echo "  ❌ [FAIL] Script taken with sed + base64 differs from the one taken with yq" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi

  _rootfs_mock
  # 3. pass the code to bash
  export PATH="${run_rootfs}/bin:${PATH}"
  export SKIPPERM=1
  echo "${bootstrap_code}" | bash -s -- ${script_args[@]+"${script_args[@]}"}

  # 4. store script to /tmp
  echo "${bootstrap_code}" > "${run_rootfs}/tmp/script.sh"
}

assert_file_exists() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "  ❌ [FAIL] Missing file: $file" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  else
    echo "  ✅ [OK] Found: $file"
  fi
}

assert_file_absent() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "  ❌ [FAIL] Unexpected file found on worker: $file" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

assert_content_matches() {
  local file="$1"
  local pattern="$2"
  local msg="$3"

# tr -d '\r' removed Windows style CRLF
if tr -d '\r' < "${file}" | grep -E -q -- "${pattern}"; then
    echo "  ✅ [OK] ${msg}"
  else
    echo "  ❌ [FAIL] Content check failed for ${file}: ${msg} (pattern: '${pattern}')" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  fi
}

assert_tgz_is_valid() {
  local file="$1"
  if ! gzip --test "$file"; then
    echo "  ❌ [FAIL] TGZ test failed: $file" >&2
    FAILURES=$((FAILURES + 1))
    return 1
  else
    echo "  ✅ [OK] TGZ test passed: $file"
  fi
}

ovrds=kubeadm/overrides

# COVERAGE matrix
#################
# NO certs
# - 1 node control plane (wihtout vip/haproxy).
# kubeadm will generate everything except service and default.
# it's ok to generate kubeconfig - it will rewrite them
run_bootstrap ""
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"

assert_logged "modprobe (br_netfilter|overlay)" "Kernel modules loaded"
assert_logged "sysctl --system"                 "Network sysctl applied"
assert_logged "swapoff"                         "Swap disabled"
assert_logged "kubeadm init"                    "Init called"

assert_before "swapoff"          "kubeadm init" "Swap disabled BEFORE kubeadm init"
assert_before "sysctl"           "kubeadm init" "Sysctl applied BEFORE kubeadm init"
assert_before "systemctl.*kubelet" "kubeadm init" "Kubelet service pre-started BEFORE kubeadm init"

# token has to be taken from controller.
# we're running without vip, so we assume that join runs as worker
run_bootstrap "" -- -- join
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"
assert_file_absent "${ROOTFS}/etc/kubernetes/manifests/kube-apiserver.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/pki/ca.key"

assert_logged "modprobe (br_netfilter|overlay)" "Kernel modules loaded"
assert_logged "sysctl --system"                 "Network sysctl applied"
assert_logged "swapoff"                         "Swap disabled"
assert_logged "kubeadm join"                    "Kubeadm join executed"

assert_before "swapoff"            "kubeadm join" "Swap disabled BEFORE kubeadm join"
assert_before "sysctl"             "kubeadm join" "Sysctl applied BEFORE kubeadm join"
assert_before "systemctl.*kubelet" "kubeadm join" "Kubelet service pre-started BEFORE kubeadm join"

# 3 nodes: with parameter
export NODE_IP="172.29.0.139"
export NODE_NAME="test-node-0"
run_bootstrap "" -- --vip_haproxy '*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- init --control-plane-endpoint="127.0.0.1:6553"

assert_logged "modprobe (br_netfilter|overlay)" "Kernel modules loaded"
assert_logged "sysctl --system"                 "Network sysctl applied"
assert_logged "swapoff"                         "Swap disabled"
assert_logged "systemctl restart kubelet"       "Kubelet service pre-started"
assert_logged "kubeadm init .*--control-plane-endpoint=127.0.0.1:6553" \
              "Kubeadm init called with correct control-plane-endpoint"

assert_before "swapoff"            "kubeadm init" "Swap disabled BEFORE kubeadm init"
assert_before "sysctl"             "kubeadm init" "Sysctl applied BEFORE kubeadm init"
assert_before "systemctl.*kubelet" "kubeadm init" "Kubelet pre-started BEFORE kubeadm init"

kubelet_env="${ROOTFS}/etc/default/kubelet"
assert_file_exists "${kubelet_env}"

assert_content_matches "${kubelet_env}" "--hostname-override=${NODE_NAME}" \
                       "Kubelet env contains correct hostname-override"
assert_content_matches "${kubelet_env}" "--node-ip=${NODE_IP}" \
                       "Kubelet env contains correct node-ip"

haproxy_cfg="${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"
assert_file_exists "${haproxy_cfg}"

assert_content_matches "${haproxy_cfg}" "bind \*:6553" \
                       "HAProxy cfg binds to *:6553"
assert_content_matches "${haproxy_cfg}" "stats socket /tmp/haproxy.sock" \
                       "HAProxy cfg has stats socket for zero-downtime reload"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.139 172.29.0.139:6443 check port 6443" \
                       "HAProxy cfg contains backend node .139"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.144 172.29.0.144:6443 check port 6443" \
                       "HAProxy cfg contains backend node .144"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.149 172.29.0.149:6443 check port 6443" \
                       "HAProxy cfg contains backend node .149"

# 2nd controller
export NODE_IP="172.29.0.144"
export NODE_NAME="test-node-1"
run_bootstrap "" -- --vip_haproxy '*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- join --control-plane --discovery-token abcdef.1234567890abcdef --discovery-token-ca-cert-hash sha256:1234..cdef 127.0.0.1:6553

assert_logged "modprobe (br_netfilter|overlay)" "Kernel modules loaded"
assert_logged "sysctl --system"                 "Network sysctl applied"
assert_logged "swapoff"                         "Swap disabled"
assert_logged "systemctl restart kubelet"       "Kubelet service pre-started"
assert_logged "kubeadm join .*127.0.0.1:6553.*" \
              "Kubeadm join called with correct control-plane-endpoint"

assert_before "swapoff"            "kubeadm join" "Swap disabled BEFORE kubeadm join"
assert_before "sysctl"             "kubeadm join" "Sysctl applied BEFORE kubeadm join"
assert_before "systemctl.*kubelet" "kubeadm join" "Kubelet pre-started BEFORE kubeadm join"

kubelet_env="${ROOTFS}/etc/default/kubelet"
assert_file_exists "${kubelet_env}"

assert_content_matches "${kubelet_env}" "--hostname-override=${NODE_NAME}" \
                       "Kubelet env contains correct hostname-override"
assert_content_matches "${kubelet_env}" "--node-ip=${NODE_IP}" \
                       "Kubelet env contains correct node-ip"

haproxy_cfg="${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"
assert_file_exists "${haproxy_cfg}"

assert_content_matches "${haproxy_cfg}" "bind \*:6553" \
                       "HAProxy cfg binds to *:6553"
assert_content_matches "${haproxy_cfg}" "stats socket /tmp/haproxy.sock" \
                       "HAProxy cfg has stats socket for zero-downtime reload"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.139 172.29.0.139:6443 check port 6443" \
                       "HAProxy cfg contains backend node .139"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.144 172.29.0.144:6443 check port 6443" \
                       "HAProxy cfg contains backend node .144"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.149 172.29.0.149:6443 check port 6443" \
                       "HAProxy cfg contains backend node .149"
#################
# CA certs
uc0_ca=(
  -f ${ovrds}/uc0.yaml
  -f ${ovrds}/pki-ca.yaml
)
export NODE_IP="172.29.0.139"
export NODE_NAME="test-node-0"
run_bootstrap "" "${uc0_ca[@]}" -- --vip_haproxy '*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- init --control-plane-endpoint="127.0.0.1:6553" --skip-phases certs/ca
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.crt"

assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/init_config.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/upgrade_config.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/join_config.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-scheduler.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/patches/etcd.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-apiserver.yaml"
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-controller-manager.yaml"

haproxy_cfg="${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"
assert_file_exists "${haproxy_cfg}"

assert_content_matches "${haproxy_cfg}" "bind \*:6553" \
                       "HAProxy cfg binds to *:6553"
assert_content_matches "${haproxy_cfg}" "stats socket /tmp/haproxy.sock" \
                       "HAProxy cfg has stats socket for zero-downtime reload"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.139 172.29.0.139:6443 check port 6443" \
                       "HAProxy cfg contains backend node .139"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.144 172.29.0.144:6443 check port 6443" \
                       "HAProxy cfg contains backend node .144"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.149 172.29.0.149:6443 check port 6443" \
                       "HAProxy cfg contains backend node .149"


# the same but with declarative kubeadm config
uc1_ca=(
  -f ${ovrds}/uc0.yaml
  -f ${ovrds}/pki-ca.yaml
  -f ${ovrds}/kubeadm.yaml
)
export NODE_IP="172.29.0.139"
export NODE_NAME="test-node-0"
run_bootstrap "" "${uc1_ca[@]}" -- --vip_haproxy '*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- init --control-plane-endpoint="127.0.0.1:6553" --skip-phases certs/ca
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.crt"

assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/init_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/upgrade_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/join_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-scheduler.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/etcd.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-apiserver.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-controller-manager.yaml"

haproxy_cfg="${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"
assert_file_exists "${haproxy_cfg}"

assert_content_matches "${haproxy_cfg}" "bind \*:6553" \
                       "HAProxy cfg binds to *:6553"
assert_content_matches "${haproxy_cfg}" "stats socket /tmp/haproxy.sock" \
                       "HAProxy cfg has stats socket for zero-downtime reload"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.139 172.29.0.139:6443 check port 6443" \
                       "HAProxy cfg contains backend node .139"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.144 172.29.0.144:6443 check port 6443" \
                       "HAProxy cfg contains backend node .144"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.149 172.29.0.149:6443 check port 6443" \
                       "HAProxy cfg contains backend node .149"


# FULL mode with vip
uc0_full_haproxy=(
  -f ${ovrds}/uc0.yaml
  -f ${ovrds}/pki-ca.yaml
  -f ${ovrds}/pki-full-node0.yaml
  -f ${ovrds}/pki-full-node1-4.yaml
  -f ${ovrds}/pki-full-genesis.yaml
  -f ${ovrds}/pki-admin.yaml
  -f ${ovrds}/kubeadm.yaml
  -f ${ovrds}/kubelet.yaml
  -f ${ovrds}/vip.yaml
  -f ${ovrds}/patch.yaml
  -f ${ovrds}/tgz.yaml
)
export NODE_IP="172.29.0.139"
export NODE_NAME="nodename1"
run_bootstrap "nodename0" "${uc0_full_haproxy[@]}"
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"

assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver-kubelet-client.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver-kubelet-client.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/front-proxy-ca.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/front-proxy-ca.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/front-proxy-client.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/front-proxy-client.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/kubelet-client-ca.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/kubelet-key.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/kubelet.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/sa.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/sa.pub"

assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/ca-peer.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/ca.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/healthcheck-client.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/healthcheck-client.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/peer.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/peer.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/server.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/server.key"

assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/cluster-ca.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/admin.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/admin-key.pem"

assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/init_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/upgrade_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/join_config.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-scheduler.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/etcd.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-apiserver.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/patches/kube-controller-manager.yaml"

assert_file_exists "${ROOTFS}/etc/kubernetes/apiserver/acconfig.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/apiserver/audit-policy.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/apiserver/encryption_provider.yaml"
assert_file_exists "${ROOTFS}/etc/kubernetes/apiserver/eventconfig.yaml"


assert_file_exists "${ROOTFS}/var/lib/kubelet/config.yaml"

haproxy_cfg="${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"
assert_file_exists "${haproxy_cfg}"

assert_content_matches "${haproxy_cfg}" "bind \*:6553" \
                       "HAProxy cfg binds to *:6553"
assert_content_matches "${haproxy_cfg}" "stats socket /tmp/haproxy.sock" \
                       "HAProxy cfg has stats socket for zero-downtime reload"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.139 172.29.0.139:6443 check port 6443" \
                       "HAProxy cfg contains backend node .139"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.144 172.29.0.144:6443 check port 6443" \
                       "HAProxy cfg contains backend node .144"
assert_content_matches "${haproxy_cfg}" "server s172.29.0.149 172.29.0.149:6443 check port 6443" \
                       "HAProxy cfg contains backend node .149"

assert_tgz_is_valid "${ROOTFS}/tmp/fs.tgz"

# FULL mode, single node control plane without vip
uc0_full_1node=(
  -f ${ovrds}/uc0.yaml
  -f ${ovrds}/pki-ca.yaml
  -f ${ovrds}/pki-full-node0.yaml
  -f ${ovrds}/pki-full-node1-4.yaml
  -f ${ovrds}/pki-full-genesis.yaml
  -f ${ovrds}/pki-admin.yaml
  -f ${ovrds}/kubeadm.yaml
  -f ${ovrds}/kubelet.yaml
)
export NODE_IP="172.29.0.139"
export NODE_NAME="nodename0"
run_bootstrap "nodename0" "${uc0_full_1node[@]}" -- -- init --skip-phases certs,kubeconfig
assert_file_exists "${ROOTFS}/etc/systemd/system/kubelet.service"
assert_file_exists "${ROOTFS}/etc/default/kubelet"
assert_file_exists "${ROOTFS}/var/lib/kubelet/config.yaml"

assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/ca.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/apiserver.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/kubelet.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/kubelet-key.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/sa.key"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/sa.pub"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/ca.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/server.crt"
assert_file_exists "${ROOTFS}/etc/kubernetes/pki/etcd/server.key"

assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/cluster-ca.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/admin.pem"
assert_file_exists "${ROOTFS}/etc/kubernetes/admin/pki/admin-key.pem"

assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration"
assert_file_exists "${ROOTFS}/etc/kubernetes/kubeadm/init_config.yaml"

# no vip: haproxy isn't configured
assert_file_absent "${ROOTFS}/etc/kubernetes/kubeadm/addons/haproxy.cfg"

assert_content_matches "${ROOTFS}/etc/default/kubelet" "--hostname-override=${NODE_NAME}" \
                       "Kubelet env contains correct hostname-override"
assert_content_matches "${ROOTFS}/etc/default/kubelet" "--node-ip=${NODE_IP}" \
                       "Kubelet env contains correct node-ip"

assert_logged "modprobe (br_netfilter|overlay)" "Kernel modules loaded"
assert_logged "sysctl --system"                 "Network sysctl applied"
assert_logged "swapoff"                         "Swap disabled"
assert_logged "kubeadm init .*--skip-phases certs,kubeconfig" \
              "Kubeadm init called with certs and kubeconfig phases skipped"

assert_before "swapoff"            "kubeadm init" "Swap disabled BEFORE kubeadm init"
assert_before "sysctl"             "kubeadm init" "Sysctl applied BEFORE kubeadm init"
assert_before "systemctl.*kubelet" "kubeadm init" "Kubelet pre-started BEFORE kubeadm init"

# # our case with VIP TBD
# uc0_full_vip=(
#   -f ${ovrds}/uc0.yaml
#   -f ${ovrds}/pki-ca.yaml
#   -f ${ovrds}/pki-full-node0.yaml
#   -f ${ovrds}/pki-full-node1-4.yaml
#   -f ${ovrds}/pki-full-genesis.yaml
# )
# # Full with HAproxy
# # Full normal init: must put all certs, add haproxy static pod, configure it and bootstrap k8s
# run_bootstrap "" "${uc0_full_haproxy[@]}"
# # Full normal join: must put all certs, add haproxy static pod, configure it and just run kubelet (it should join)
# run_bootstrap "nodename1" "${uc0_full_haproxy[@]}"
# # Full with manual haproxy override. the use-case is - limit haproxy list to 3
# run_bootstrap "" "${uc0_full_haproxy[@]}" -- vip_haproxy='*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443'
# # + some extra params to kubeadm to make sure it passes
# run_bootstrap "" "${uc0_full_haproxy[@]}" -- vip_haproxy='*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- join --pod-network-cidr=10.244.0.0/16
# # Full per-node init. use case is - we start not from genesis, but from any controller
# run_bootstrap "nodename0" "${uc0_full_haproxy[@]}" -- vip_haproxy='*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443'
# # Full per-node join with extra params
# run_bootstrap "nodename1" "${uc0_full_haproxy[@]}" -- vip_haproxy='*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443'
# run_bootstrap "nodename1" "${uc0_full_haproxy[@]}" -- vip_haproxy='*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443' -- join --pod-network-cidr=10.244.0.0/16

# # Full with external VIP (haproxy isn't enabled)
# run_bootstrap "" "${uc0_full_vip[@]}"
# # Full normal join: must put all certs, add haproxy static pod, configure it and just run kubelet (it should join)
# run_bootstrap "nodename1" "${uc0_full_vip[@]}"
# # + some extra params to kubeadm to make sure it passes
# run_bootstrap "" "${uc0_full_haproxy[@]}" -- -- --pod-network-cidr=10.244.0.0/16
# # Full per-node init. use case is - we start not from genesis, but from any controller
# # Full per-node join with extra params
# run_bootstrap "nodename1" "${uc0_full_haproxy[@]}" -- -- --pod-network-cidr=10.244.0.0/16

# tar: a hardlink target sorted after the link is written once, '%' in a path,
# a long path (USTAR prefix), root owner, reproducible with an explicit mtime

echo "[tar] links, '%' in a path, long path, owner, reproducibility"
tar_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] tar: ${msg}"
  else
    echo "  ❌ [FAIL] tar: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
tar_chart=$(mktemp -d)
mkdir -p "${tar_chart}/templates" "${tar_chart}/out"
cp kubeadm/templates/lib/_tar.tpl "${tar_chart}/templates/"
printf 'apiVersion: v2\nname: tar-test\nversion: 0.1.0\n' > "${tar_chart}/Chart.yaml"
cat > "${tar_chart}/templates/configmap.yaml" << 'EOF'
{{- $long := print (repeat 12 "longdir/") (repeat 8 "longname") -}}
{{- $files := dict
    "a.link" (dict "type" "1" "link_path" "z" "mod_timestamp" 0)
    "z" (dict "content" "z\n" "mod_timestamp" 0)
    "x/100%done" (dict "content" "pct\n" "mod_timestamp" 0)
    $long (dict "content" "long\n" "mod_timestamp" 0) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: tar-test
data:
  tar: {{ $files | include "tar" | b64enc }}
EOF
tar_long="$(printf 'longdir/%.0s' {1..12})$(printf 'longname%.0s' {1..8})"
"${HELM:-helm}" template tar-test "${tar_chart}" | sed -n 's/^  tar: //p' | base64 -d > "${tar_chart}/1.tar"
# another second: the archive would differ with the default mtime (now)
sleep 1
"${HELM:-helm}" template tar-test "${tar_chart}" | sed -n 's/^  tar: //p' | base64 -d > "${tar_chart}/2.tar"
tar_check "the same archive on every render" cmp -s "${tar_chart}/1.tar" "${tar_chart}/2.tar"
tar_check "every entry is written once" test \
  "$(tar -tf "${tar_chart}/1.tar" | sort)" = "$(printf '%s\n' a.link "${tar_long}" 'x/100%done' z | sort)"
tar_check "hardlink" grep -q 'a\.link link to z$' <(tar -tvf "${tar_chart}/1.tar")
# read from the first header: the listing format differs between GNU tar and bsdtar
tar_owner=$(for f in 108:6 116:6 265:4 297:4; do
  dd if="${tar_chart}/1.tar" bs=1 skip="${f%:*}" count="${f#*:}" 2>/dev/null; echo
done)
tar_check "root owner" test "$(echo ${tar_owner})" = "000000 000000 root root"
tar_check "extraction" tar -xf "${tar_chart}/1.tar" -C "${tar_chart}/out"
tar_check "'%' in a path" test "$(cat "${tar_chart}/out/x/100%done")" = pct
tar_check "long path" test "$(cat "${tar_chart}/out/${tar_long}")" = long
rm -rf "${tar_chart}"

# gzip of incompressible data: STORED blocks, also after a compressed one, and
# without compression (text_random and stored have 2 blocks, the max block size
# is 65535)

echo "[gzip] incompressible data and no compression"
gzip_chart=$(mktemp -d)
mkdir -p "${gzip_chart}/templates"
cp kubeadm/templates/lib/_gzip.tpl "${gzip_chart}/templates/"
printf 'apiVersion: v2\nname: gzip-test\nversion: 0.1.0\n' > "${gzip_chart}/Chart.yaml"
cat > "${gzip_chart}/templates/configmap.yaml" << 'EOF'
{{- $random := randBytes 3000 | b64dec -}}
{{- $textRandom := print (repeat 5500 "hello world ") $random -}}
{{- $cases := dict
    "random" (dict "content" $random)
    "text_random" (dict "content" $textRandom)
    "stored" (dict "content" $textRandom "compress" false) -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: gzip-test
data:
{{- range $name, $case := $cases }}
  {{ $name }}: {{ $case.content | b64enc }}
  {{ $name }}_gz: {{ $case | include "gzip" | b64enc }}
{{- end }}
EOF
gzip_rendered=$("${HELM:-helm}" template gzip-test "${gzip_chart}")
for name in random text_random stored; do
  echo "${gzip_rendered}" | sed -n "s/^  ${name}: //p" | base64 -d > "${gzip_chart}/${name}"
  echo "${gzip_rendered}" | sed -n "s/^  ${name}_gz: //p" | base64 -d > "${gzip_chart}/${name}.gz"
  if gzip -dc "${gzip_chart}/${name}.gz" | cmp -s - "${gzip_chart}/${name}"; then
    echo "  ✅ [OK] gzip round trip: ${name}"
  else
    echo "  ❌ [FAIL] gzip round trip: ${name}" >&2
    FAILURES=$((FAILURES + 1))
  fi
done
rm -rf "${gzip_chart}"

# files: every state, the mode is applied, the second sync with nothing to
# change (unchanged files, an absent file to remove) doesn't stop the script

echo "[files] states, mode, second sync"
files_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] files: ${msg}"
  else
    echo "  ❌ [FAIL] files: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
files_mode() {
  stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"
}
files_chart=$(mktemp -d)
mkdir -p "${files_chart}/templates" "${files_chart}/rootfs"
cp kubeadm/templates/phases/_fs.tpl kubeadm/templates/lib/bundle/_template.tpl kubeadm/templates/lib/_tar.tpl "${files_chart}/templates/"
printf 'apiVersion: v2\nname: files-test\nversion: 0.1.0\n' > "${files_chart}/Chart.yaml"
cat > "${files_chart}/values.yaml" << 'EOF'
word: rendered
bundle:
  tpl:
    file.tpl: "{{ .Values.word }}\n"
files:
  test:
    - path: /d
      state: dir
      mode: "0750"
    - path: /d/content
      state: content
      from: "content\n"
      mode: "0640"
    - path: /d/tpl
      state: tpl
      from: file.tpl
    - path: /d/copy
      state: copy
      from: /d/content
    - path: /d/touched
      state: touch
    - path: /d/removed
      state: touch
    - path: /d/removed
      state: rm
    - path: /d/absent
      state: rm
EOF
cat > "${files_chart}/templates/configmap.yaml" << 'EOF'
{{- $conf := dict "sharedLibs" (dict) "fs" (dict "all" (dict)) -}}
{{- $_ := include "files-test/templates/_fs.tpl" (tuple . $conf "fs") -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: files-test
data:
  lib: {{ $conf.sharedLibs.fs | b64enc }}
  tar: {{ $conf.fs.all | include "tar" | b64enc }}
EOF
files_rendered=$("${HELM:-helm}" template files-test "${files_chart}")
echo "${files_rendered}" | sed -n 's/^  lib: //p' | base64 -d > "${files_chart}/lib.sh"
# the files of the chart are in /run/kubeadm on the node (ensure_fs)
mkdir -p "${files_chart}/rootfs/run/kubeadm/all"
echo "${files_rendered}" | sed -n 's/^  tar: //p' | base64 -d | tar -x -C "${files_chart}/rootfs/run/kubeadm/all"
# returns the status of sync_test: 0 changed, 1 unchanged, 2 if it didn't finish
files_sync() {
  local rc=0
  ROOTFS="${files_chart}/rootfs" SKIPPERM= bash -c 'set -euo pipefail; source "$1"; sync_test' _ "${files_chart}/lib.sh" > "${files_chart}/out" || rc=$?
  grep -qx "test is synced" "${files_chart}/out" || return 2
  return "${rc}"
}
files_unchanged() {
  local rc=0
  files_sync || rc=$?
  [ "${rc}" -eq 1 ]
}
files_d="${files_chart}/rootfs/d"
files_check "first sync changes files" files_sync
files_check "dir mode" test "$(files_mode "${files_d}")" = 750
files_check "content" test "$(cat "${files_d}/content")" = content
files_check "content mode" test "$(files_mode "${files_d}/content")" = 640
files_check "tpl" test "$(cat "${files_d}/tpl")" = rendered
files_check "copy" cmp -s "${files_d}/content" "${files_d}/copy"
files_check "touch" test -f "${files_d}/touched"
files_check "rm" test ! -e "${files_d}/removed"
# base64 of the content and tpl files: they come from the fs, not the script
files_not_inlined() {
  ! grep -q -e Y29udGVudAo= -e cmVuZGVyZWQK "${files_chart}/lib.sh"
}
files_check "content isn't in the script" files_not_inlined
files_check "second sync changes nothing" files_unchanged
rm -rf "${files_chart}"

echo
if [[ "${FAILURES}" -gt 0 ]]; then
  echo "❌ ${FAILURES} check(s) failed" >&2
  exit 1
fi
echo "✅ All checks passed"
