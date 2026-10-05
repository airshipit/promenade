#!/bin/sh

#set -euo pipefail

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
    return 1
  else
    echo "  ✅ [OK] Found: $file"
  fi
}

assert_file_absent() {
  local file="$1"
  if [[ -f "$file" ]]; then
    echo "  ❌ [FAIL] Unexpected file found on worker: $file" >&2
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
    return 1
  fi
}

assert_tgz_is_valid() {
  local file="$1"
  if ! gzip --test "$file"; then
    echo "  ❌ [FAIL] TGZ test failed: $file" >&2
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
