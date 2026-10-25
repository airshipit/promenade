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
  # the node checks need a running node
  local extra_helm_args="--set checks.bootstrap=false"
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

ovrds=kubeadm/overrides/test

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

# patches of the templates (bundle.tpl."<template>.patch", overrides/test/patch.yaml):
# the patch is applied, the lists are merged (the rest of the template stays)

echo "[patches] daemonsets, kubelet restart job, haproxy static pod"
patches_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] patches: ${msg}"
  else
    echo "  ❌ [FAIL] patches: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
patches_dir=$(mktemp -d)
"${HELM:-helm}" template kubeadm kubeadm -f kubeadm/overrides/test/patch.yaml > "${patches_dir}/rendered.yaml"
# the value of the yq expression in the file is the expected one
patches_eq() {
  [ "$("${YQ:-yq}" "$2" "$1")" = "$3" ]
}
patches_ds='select(.kind == "DaemonSet" and .metadata.name == "kubeadm-service-'
patches_check "masters: the field is patched" patches_eq "${patches_dir}/rendered.yaml" \
  "${patches_ds}masters-anchor\") | .spec.template.spec.terminationGracePeriodSeconds" 2400
patches_check "workers: the field is patched" patches_eq "${patches_dir}/rendered.yaml" \
  "${patches_ds}workers-anchor\") | .spec.template.spec.terminationGracePeriodSeconds" 1200
patches_check "masters: env is merged" patches_eq "${patches_dir}/rendered.yaml" \
  "${patches_ds}masters-anchor\") | .spec.template.spec.containers[0].env[] | select(.name == \"NODE_NAME\" or .name == \"TEST_ENV\") | .name" \
  "$(printf 'NODE_NAME\nTEST_ENV')"
# the job is in the reconcile script
"${YQ:-yq}" 'select(.kind == "ConfigMap" and .metadata.name == "kubeadm-service-bin") | .data.reconcile' "${patches_dir}/rendered.yaml" \
  | awk '/^EOF_DATA/ { f = 0 } f; /job_name=\$\(kubectl create/ { f = 1 }' > "${patches_dir}/job.yaml"
patches_check "job: the container is patched" patches_eq "${patches_dir}/job.yaml" \
  '.spec.template.spec.containers[0].securityContext.appArmorProfile.type' RuntimeDefault
patches_check "job: the container keeps its fields" patches_eq "${patches_dir}/job.yaml" \
  '.spec.template.spec.containers[0].securityContext.privileged' true
patches_check "job: images.pull_policy" patches_eq "${patches_dir}/job.yaml" \
  '.spec.template.spec.containers[0].imagePullPolicy' IfNotPresent
# the static pod is in the archive of the files of all the nodes
"${YQ:-yq}" 'select(.kind == "Secret" and .metadata.name == "kubeadm-service-fs-all") | .data["all.tar"]' "${patches_dir}/rendered.yaml" \
  | base64 -d | tar -xO -f - _manifests/haproxy.yaml > "${patches_dir}/haproxy.yaml"
patches_check "haproxy: the annotation is added" patches_eq "${patches_dir}/haproxy.yaml" \
  '.metadata.annotations["test-annotation"]' test-value
patches_check "haproxy: the container stays" patches_eq "${patches_dir}/haproxy.yaml" \
  '.spec.containers[0].name' haproxy
rm -rf "${patches_dir}"

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

# strategic merge patch: maps, null, $patch directives, lists merged by the
# key in the order of the base, other lists replaced, an own schema
# (the one of the chart extended), the base isn't modified, the errors

echo "[smp] strategic merge patch"
smp_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] smp: ${msg}"
  else
    echo "  ❌ [FAIL] smp: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
smp_chart=$(mktemp -d)
mkdir -p "${smp_chart}/templates"
cp kubeadm/templates/lib/_smp_lt.tpl "${smp_chart}/templates/"
printf 'apiVersion: v2\nname: smp-test\nversion: 0.1.0\n' > "${smp_chart}/Chart.yaml"
cat > "${smp_chart}/values.yaml" << 'EOF'
# a string parsed by fromYaml: helm drops the null values of the values (and
# YAML 1.1 booleans like y or n are avoided in the keys)
cases: |
    maps:
      base: {a: 1, b: keep, m: {x: 1, w: 2}}
      patch: {a: 2, m: {w: 3, z: 4}, p: {new: true}}
      expected: {a: 2, b: keep, m: {x: 1, w: 3, z: 4}, p: {new: true}}
    null_field:
      base: {a: 1, b: 2, m: {x: 1, w: 2}}
      patch: {a: null, m: {x: null}}
      expected: {b: 2, m: {w: 2}}
    map_replace:
      base: {m: {x: 1, w: 2}}
      patch: {m: {$patch: replace, z: 3}}
      expected: {m: {z: 3}}
    map_delete:
      base: {m: {x: 1}, k: 1}
      patch: {m: {$patch: delete}}
      expected: {k: 1}
    list_replace:
      base: {args: [a, b], items: [{name: x}]}
      patch: {args: [c], items: [{name: q}]}
      expected: {args: [c], items: [{name: q}]}
    daemonset:
      gvk: apps/v1/DaemonSet
      base:
        apiVersion: apps/v1
        kind: DaemonSet
        spec:
          template:
            spec:
              initContainers: [{name: i2, image: i2}, {name: i1, image: i1}]
              containers:
                - name: b
                  image: b:1
                  env: [{name: Z, value: z}, {name: A, value: a}]
                  volumeMounts: [{name: v, mountPath: /v}]
                  args: [x, q]
                - name: a
                  image: a:1
                - name: c
                  image: c:1
              tolerations: [{key: k1}]
      patch:
        spec:
          template:
            spec:
              initContainers: [{name: i1, image: i1:2}]
              containers:
                - name: new
                  image: new:1
                  env: [{name: N, value: nv, valueFrom: null}]
                - name: b
                  image: b:2
                  env: [{name: A, value: a2}, {name: M, value: m}, {name: Z, $patch: delete}]
                  volumeMounts: [{name: w, mountPath: /w}]
                  args: [z]
                - name: c
                  $patch: delete
                - name: gone
                  $patch: delete
              tolerations: [{key: k2}]
      expected:
        apiVersion: apps/v1
        kind: DaemonSet
        spec:
          template:
            spec:
              initContainers: [{name: i2, image: i2}, {name: i1, image: i1:2}]
              containers:
                - name: b
                  image: b:2
                  env: [{name: A, value: a2}, {name: M, value: m}]
                  volumeMounts: [{name: v, mountPath: /v}, {name: w, mountPath: /w}]
                  args: [z]
                - name: a
                  image: a:1
                - name: new
                  image: new:1
                  env: [{name: N, value: nv}]
              tolerations: [{key: k2}]
    list_replace_directive:
      gvk: v1/Pod
      base: {apiVersion: v1, kind: Pod, spec: {volumes: [{name: a}, {name: b}]}}
      patch: {spec: {volumes: [{$patch: replace}, {name: c}]}}
      expected: {apiVersion: v1, kind: Pod, spec: {volumes: [{name: c}]}}
    podspec:
      gvk: v1/PodSpec
      base: {containers: [{name: a, image: a:1}, {name: b, image: b:1}]}
      patch: {containers: [{name: b, image: b:2}]}
      expected: {containers: [{name: a, image: a:1}, {name: b, image: b:2}]}
    service_ports:
      gvk: v1/Service
      base: {apiVersion: v1, kind: Service, spec: {ports: [{port: 80, name: http}, {port: 443, name: https}]}}
      patch: {spec: {ports: [{port: 443, targetPort: 8443}, {port: 8080}]}}
      expected: {apiVersion: v1, kind: Service, spec: {ports: [{port: 80, name: http}, {port: 443, name: https, targetPort: 8443}, {port: 8080}]}}
    # the schema of the chart extended with an own type
    custom_schema:
      gvk: example/v1/Thing
      schema:
        example/v1/Thing:
          items: {strategy: merge, key: id}
          pod: {$ref: v1/PodSpec}
      base: {items: [{id: 1, v: a}, {id: 2, v: b}], pod: {containers: [{name: a, image: a:1}]}}
      patch: {items: [{id: 2, v: c}], pod: {containers: [{name: b, image: b:1}]}}
      expected: {items: [{id: 1, v: a}, {id: 2, v: c}], pod: {containers: [{name: a, image: a:1}, {name: b, image: b:1}]}}
    # the pod spec deep in the cronjob, the lists of the pod spec and the container
    cronjob:
      gvk: batch/v1/CronJob
      base:
        spec:
          jobTemplate:
            spec:
              template:
                spec:
                  containers: [{name: a, image: a:1, resizePolicy: [{resourceName: cpu, restartPolicy: NotRequired}]}]
                  schedulingGates: [{name: g1}]
                  resourceClaims: [{name: r1}]
      patch:
        spec:
          jobTemplate:
            spec:
              template:
                spec:
                  containers: [{name: a, resizePolicy: [{resourceName: memory, restartPolicy: RestartContainer}]}]
                  ephemeralContainers: [{name: debug, image: busybox}]
                  schedulingGates: [{name: g2}]
                  resourceClaims: [{name: r1, resourceClaimName: claim}]
      expected:
        spec:
          jobTemplate:
            spec:
              template:
                spec:
                  containers: [{name: a, image: a:1, resizePolicy: [{resourceName: cpu, restartPolicy: NotRequired}, {resourceName: memory, restartPolicy: RestartContainer}]}]
                  ephemeralContainers: [{name: debug, image: busybox}]
                  schedulingGates: [{name: g1}, {name: g2}]
                  resourceClaims: [{name: r1, resourceClaimName: claim}]
    podtemplate:
      gvk: v1/PodTemplate
      base: {template: {spec: {containers: [{name: a, image: a:1}]}}}
      patch: {template: {spec: {containers: [{name: b, image: b:1}]}}}
      expected: {template: {spec: {containers: [{name: a, image: a:1}, {name: b, image: b:1}]}}}
    # a rule added to the daemonset doesn't change the deployment
    extend_isolated:
      gvk: apps/v1/Deployment
      extend:
        apps/v1/DaemonSet:
          spec.items: {strategy: merge, key: id}
      base: {spec: {items: [{id: 1}]}}
      patch: {spec: {items: [{id: 2}]}}
      expected: {spec: {items: [{id: 2}]}}
EOF
cat > "${smp_chart}/templates/configmap.yaml" << 'EOF'
{{- $error := .Values.error | default "" -}}
{{- if eq $error "not_empty" -}}
{{- $_ := include "strategic_merge_patch" (tuple (dict) "" (dict) (dict) (dict "x" 1)) -}}
{{- else if eq $error "directive" -}}
{{- $_ := include "strategic_merge_patch" (tuple (dict) "" (dict) (dict "$retainKeys" (list "a")) (dict)) -}}
{{- else if eq $error "gvk" -}}
{{- $_ := include "strategic_merge_patch" (tuple (dict) nil (dict) (dict) (dict)) -}}
{{- else if eq $error "schema" -}}
{{- $_ := include "strategic_merge_patch" (tuple (list) "" (dict) (dict) (dict)) -}}
{{- end -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: smp-test
data:
{{- range $name, $c := fromYaml .Values.cases }}
  {{- $before := toJson $c.base }}
  {{- $out := dict }}
  {{- $schema := dict }}
  {{- $_ := include "strategic_merge_patch_schema" $schema }}
  {{- range $k, $v := $c.schema }}{{ $_ := set $schema $k $v }}{{ end }}
  {{- range $gvk, $rules := $c.extend }}{{ range $path, $rule := $rules }}{{ $_ := set (index $schema $gvk) $path $rule }}{{ end }}{{ end }}
  {{- $_ := include "strategic_merge_patch" (tuple $schema ($c.gvk | default "") $c.base $c.patch $out) }}
  {{ $name }}: {{ if eq (toJson $out) (toJson $c.expected) }}OK{{ else }}{{ toJson $out | quote }}{{ end }}
  {{ $name }}_base: {{ if eq (toJson $c.base) $before }}OK{{ else }}{{ toJson $c.base | quote }}{{ end }}
{{- end }}
EOF
smp_rendered=$("${HELM:-helm}" template smp-test "${smp_chart}" 2>&1)
smp_result() {
  local line
  line=$(echo "${smp_rendered}" | sed -n "s/^  $1: //p")
  [ "${line}" = OK ] && return 0
  echo "    got: ${line:-${smp_rendered}}" >&2
  return 1
}
for name in maps null_field map_replace map_delete list_replace daemonset list_replace_directive podspec service_ports custom_schema cronjob podtemplate extend_isolated; do
  smp_check "${name}" smp_result "${name}"
  smp_check "${name}: the base isn't modified" smp_result "${name}_base"
done
# the rendering fails with the message
smp_fails() {
  local out
  out=$("${HELM:-helm}" template smp-test "${smp_chart}" --set "error=$1" 2>&1) && return 1
  grep -q "$2" <<< "${out}"
}
smp_check "fails if the dict for the result isn't empty" smp_fails not_empty "must be empty"
smp_check "fails on an unsupported directive" smp_fails directive 'unsupported directive \$retainKeys'
smp_check "fails if the gvk isn't a string" smp_fails gvk "the gvk must be a string"
smp_check "fails if the schema isn't a dict" smp_fails schema "the schema must be a dict"
rm -rf "${smp_chart}"

# tools: gen-pki.sh extracted from the chart (manifests.secret_tools) generates
# the CAs and the service account key as a values override the chart takes,
# the errors of openssl are shown

echo "[tools] gen-pki.sh"
tools_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] tools: ${msg}"
  else
    echo "  ❌ [FAIL] tools: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
tools_dir=$(mktemp -d)
"${HELM:-helm}" template kubeadm kubeadm --set manifests.secret_tools=true \
  | sed -n 's/^ *gen-pki.sh: *\(.*\)/\1/p' | base64 -d > "${tools_dir}/gen-pki.sh"
tools_values="${tools_dir}/out/values-pki.yaml"
tools_check "generates the values" bash "${tools_dir}/gen-pki.sh" --out-file "${tools_values}" --days 30
tools_check "the values aren't readable by others" test "$(stat -c %a "${tools_values}" 2>/dev/null || stat -f %Lp "${tools_values}")" = 600
tools_check "the certs" test "$("${YQ:-yq}" '.certs | keys | join(" ")' "${tools_values}")" = "ca etcd_ca front_proxy_ca sa"
# the pem of the values to a file
tools_pem() {
  "${YQ:-yq}" ".certs.$1" "${tools_values}" > "${tools_dir}/$2"
}
tools_ca() {
  local name="$1" cn="$2"
  tools_pem "${name}.crt" "${name}.crt" && tools_pem "${name}.key" "${name}.key" &&
    openssl verify -CAfile "${tools_dir}/${name}.crt" "${tools_dir}/${name}.crt" > /dev/null &&
    openssl x509 -in "${tools_dir}/${name}.crt" -noout -subject | grep -q "CN *= *${cn}$" &&
    openssl x509 -in "${tools_dir}/${name}.crt" -noout -text | grep -q "CA:TRUE" &&
    # --days 30: valid in 29 days, not in 31
    openssl x509 -in "${tools_dir}/${name}.crt" -noout -checkend $((29 * 86400)) > /dev/null &&
    ! openssl x509 -in "${tools_dir}/${name}.crt" -noout -checkend $((31 * 86400)) > /dev/null &&
    test "$(openssl x509 -in "${tools_dir}/${name}.crt" -noout -pubkey)" = \
      "$(openssl pkey -in "${tools_dir}/${name}.key" -pubout)"
}
tools_check "ca: self-signed CA with its key" tools_ca ca kubernetes
tools_check "etcd_ca: self-signed CA with its key" tools_ca etcd_ca etcd-ca
tools_check "front_proxy_ca: self-signed CA with its key" tools_ca front_proxy_ca front-proxy-ca
tools_sa() {
  tools_pem sa.key sa.key && tools_pem sa.pub sa.pub &&
    test "$(openssl pkey -in "${tools_dir}/sa.key" -pubout)" = "$(cat "${tools_dir}/sa.pub")"
}
tools_check "sa: the key pair" tools_sa
# the chart with the generated values: the CA goes to the control plane nodes
# (fingerprints: yq adds a newline to the pem)
tools_chart() {
  local crt
  crt=$("${HELM:-helm}" template kubeadm kubeadm -f "${tools_values}" \
    | "${YQ:-yq}" 'select(.kind == "Secret" and .metadata.name == "kubeadm-service-fs-ctrl") | .data["ctrl.tar"]' \
    | base64 -d | tar -xO -f - _pkipub/ca.crt) || return 1
  test "$(openssl x509 -noout -fingerprint <<< "${crt}")" = \
    "$(openssl x509 -in "${tools_dir}/ca.crt" -noout -fingerprint)"
}
tools_check "the chart takes the values" tools_chart
tools_error() {
  local out
  out=$(bash "${tools_dir}/gen-pki.sh" --out-file "${tools_dir}/error.yaml" --days invalid 2>&1) && return 1
  grep -q "openssl req failed" <<< "${out}"
}
tools_check "the error of openssl is shown" tools_error
rm -rf "${tools_dir}"

# for a parent cluster: the CA and the admin client certificate as tls
# Secrets, the admin one either from certs.admin or by cert-manager

echo "[parent] tls secrets, cert-manager"
parent_check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ [OK] parent: ${msg}"
  else
    echo "  ❌ [FAIL] parent: ${msg}" >&2
    FAILURES=$((FAILURES + 1))
  fi
}
parent_dir=$(mktemp -d)
parent_pki=(-f kubeadm/overrides/test/pki-ca.yaml -f kubeadm/overrides/test/pki-admin.yaml)
"${HELM:-helm}" template kubeadm kubeadm > "${parent_dir}/default.yaml"
"${HELM:-helm}" template kubeadm kubeadm "${parent_pki[@]}" \
  --set manifests.secret_ca_tls=true --set manifests.secret_admin_tls=true > "${parent_dir}/values.yaml"
"${HELM:-helm}" template kubeadm kubeadm "${parent_pki[@]}" \
  --set manifests.secret_ca_tls=true --set manifests.cert_manager_admin=true > "${parent_dir}/cert-manager.yaml"
# the value of the yq expression on the object of the file is the expected one
parent_eq() {
  [ "$("${YQ:-yq}" "select(.kind == \"$2\" and .metadata.name == \"$3\") | $4" "${parent_dir}/$1")" = "$5" ]
}
parent_absent() {
  [ -z "$("${YQ:-yq}" 'select(.metadata.name == "kubeadm-service-ca" or .metadata.name == "kubeadm-service-admin") | .kind' "${parent_dir}/default.yaml")" ]
}
parent_check "nothing by default" parent_absent
parent_check "ca: tls secret" parent_eq values.yaml Secret kubeadm-service-ca .type kubernetes.io/tls
parent_check "ca: certificate" parent_eq values.yaml Secret kubeadm-service-ca '.data["tls.crt"] | @base64d' ca-crt-placeholder
parent_check "ca: key" parent_eq values.yaml Secret kubeadm-service-ca '.data["tls.key"] | @base64d' ca-key-placeholder
parent_check "admin from values: tls secret" parent_eq values.yaml Secret kubeadm-service-admin .type kubernetes.io/tls
parent_check "admin from values: certificate" parent_eq values.yaml Secret kubeadm-service-admin '.data["tls.crt"] | @base64d' admin-crt-placeholder
parent_check "admin from values: key" parent_eq values.yaml Secret kubeadm-service-admin '.data["tls.key"] | @base64d' admin-key-placeholder
parent_check "admin from values: ca" parent_eq values.yaml Secret kubeadm-service-admin '.data["ca.crt"] | @base64d' ca-crt-placeholder
parent_check "cert-manager: issuer on the ca secret" parent_eq cert-manager.yaml Issuer kubeadm-service-ca .spec.ca.secretName kubeadm-service-ca
parent_check "cert-manager: the same admin secret" parent_eq cert-manager.yaml Certificate kubeadm-service-admin .spec.secretName kubeadm-service-admin
parent_check "cert-manager: issued by the issuer" parent_eq cert-manager.yaml Certificate kubeadm-service-admin .spec.issuerRef.name kubeadm-service-ca
parent_check "cert-manager: group" parent_eq cert-manager.yaml Certificate kubeadm-service-admin '.spec.subject.organizations[0]' kubeadm:cluster-admins
parent_check "cert-manager: client certificate" parent_eq cert-manager.yaml Certificate kubeadm-service-admin '.spec.usages[0]' "client auth"
parent_check "cert-manager: no admin secret rendered" parent_eq cert-manager.yaml Secret kubeadm-service-admin .kind ""
# the rendering fails with the message
parent_fails() {
  local msg="$1" out
  shift
  out=$("${HELM:-helm}" template kubeadm kubeadm "$@" 2>&1) && return 1
  grep -q "${msg}" <<< "${out}"
}
parent_check "both admin secrets fail" parent_fails "enable one of them" "${parent_pki[@]}" \
  --set manifests.secret_admin_tls=true --set manifests.cert_manager_admin=true
parent_check "ca without certs fails" parent_fails "needs certs.ca.crt and certs.ca.key" \
  --set manifests.secret_ca_tls=true
parent_check "admin without certs fails" parent_fails "needs certs.admin.crt" -f kubeadm/overrides/test/pki-ca.yaml \
  --set manifests.secret_admin_tls=true
rm -rf "${parent_dir}"

echo
if [[ "${FAILURES}" -gt 0 ]]; then
  echo "❌ ${FAILURES} check(s) failed" >&2
  exit 1
fi
echo "✅ All checks passed"
