{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $allNodes := get (get $k8sConfDict "fs") "all" -}}
{{- $controlPlaneNodes := get (get $k8sConfDict "fs") "ctrl" -}}

{{- $folder2prefix:= dict
      "." (tuple "kubeadm_" $allNodes)
      "patches" (tuple "kubeadmpatch_" $allNodes)
      "/etc/kubernetes/apiserver" (tuple "kubeadmapiserver_" $controlPlaneNodes)
-}}

{{- if $envAll.Values.kubeadm -}}
  {{- if $envAll.Values.kubeadm.templates -}}
    {{- range $filename,$template := $envAll.Values.kubeadm.templates -}}
      {{/* account for different directories. fail if no matiching prefix */}}
      {{- $fname := base $filename -}}
      {{- $fdir := dir $filename -}}
      {{- if not (hasKey $folder2prefix $fdir) -}}{{ fail (printf "templates/phases/modules/kubeadm/_.tpl doesn't know how to treat files in %s (filename %s)" $fdir $filename) }}{{- end -}}
      {{- $ftuple := get $folder2prefix $fdir -}}
      {{- $_ := set (index $ftuple 1) (printf "_%s/%s" (trimSuffix "_" (index $ftuple 0)) $fname) (dict "content" (tuple $envAll $template | include "kubeadm.bundle.template") "dest_path" "/etc/kubernetes/kubeadm/cluster_config.yaml") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- define "__kubeadm_sync" -}}
{{- $envAll := . -}}
{{- $kubernetesKubeadmDirMode := tuple $envAll "/etc/kubernetes/kubeadm" | include "kubeadm.fs.dir_mode" -}}
{{- $kubernetesKubeadmDirOwner := tuple $envAll "/etc/kubernetes/kubeadm" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeadmMode := tuple $envAll "kubeadm" "kubeadm" | include "kubeadm.fs.file_mode" -}}
{{- $kubeadmOwner := tuple $envAll "kubeadm" "kubeadm" | include "kubeadm.fs.file_owner" -}}
{{- $kubernetesKubeadmPatchesDirMode := tuple $envAll "/etc/kubernetes/kubeadm/patches" | include "kubeadm.fs.dir_mode" -}}
{{- $kubernetesKubeadmPatchesDirOwner := tuple $envAll "/etc/kubernetes/kubeadm/patches" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeadmpatchMode := tuple $envAll "kubeadm" "kubeadmpatch" | include "kubeadm.fs.file_mode" -}}
{{- $kubeadmpatchOwner := tuple $envAll "kubeadm" "kubeadmpatch" | include "kubeadm.fs.file_owner" -}}
{{- $kubernetesApiserverDirMode := tuple $envAll "/etc/kubernetes/apiserver" | include "kubeadm.fs.dir_mode" -}}
{{- $kubernetesApiserverDirOwner := tuple $envAll "/etc/kubernetes/apiserver" | include "kubeadm.fs.dir_owner" -}}
{{- $kubeadmapiserverMode := tuple $envAll "kubeadm" "kubeadmapiserver" | include "kubeadm.fs.file_mode" -}}
{{- $kubeadmapiserverOwner := tuple $envAll "kubeadm" "kubeadmapiserver" | include "kubeadm.fs.file_owner" -}}
kubeadm_sync() {
  local kubernetes_dir="/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm" "{{ $kubernetesKubeadmDirMode }}" "{{ $kubernetesKubeadmDirOwner }}"
  group_dir_sync "${ROOTFS}" "_kubeadm" "${kubernetes_dir}/kubeadm" "${NODE_ROLE}" true "{{ $kubeadmMode }}" "{{ $kubeadmOwner }}"
  # init config must include ClusterConfiguration
  if [ -f "${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml" ]; then
    echo "---" >> "${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml"
    cat "${ROOTFS}${kubernetes_dir}/kubeadm/ClusterConfiguration" >> "${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml"
  fi

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm/patches" "{{ $kubernetesKubeadmPatchesDirMode }}" "{{ $kubernetesKubeadmPatchesDirOwner }}"
  group_dir_sync "${ROOTFS}" "_kubeadmpatch" "${kubernetes_dir}/kubeadm/patches" "${NODE_ROLE}" false "{{ $kubeadmpatchMode }}" "{{ $kubeadmpatchOwner }}"

  if [ "${NODE_ROLE}" == "master" ]; then
    ensure_dir "${ROOTFS}${kubernetes_dir}/apiserver" "{{ $kubernetesApiserverDirMode }}" "{{ $kubernetesApiserverDirOwner }}"
    group_dir_sync "${ROOTFS}" "_kubeadmapiserver" "${kubernetes_dir}/apiserver" "${NODE_ROLE}" false "{{ $kubeadmapiserverMode }}" "{{ $kubeadmapiserverOwner }}"
  fi
  echo "kubeadm is synced"
}
{{- end -}}
{{- $_ := set $symbols "kubeadm_sync" (dict "needs" (list "ensure_dir" "group_dir_sync")
"body" (include "__kubeadm_sync" $envAll)
) -}}

{{- $_ := set $symbols "annotations" (dict "body" `
# the annotations of the node with the configurations it runs with: the
# reconcile script applies the kubeadm (control plane nodes) and the kubelet
# configuration only if the node runs with another one
KUBEADM_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_ANNOTATION="last-applied-kubelet-cfg-sha256"
`) -}}

{{- $_ := set $symbols "kubeadm_config_sha256" (dict "body" `
kubeadm_config_sha256() {
  sha256sum < "${ROOTFS}/run/kubeadm/all/_kubeadm/ClusterConfiguration" | cut -d ' ' -f 1
}
`) -}}

{{- $_ := set $symbols "kubelet_config_sha256" (dict "body" `
kubelet_config_sha256() {
  sha256sum < "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet_config.yaml" | cut -d ' ' -f 1
}
`) -}}

{{- define "__annotate_applied" -}}
{{- $envAll := . -}}
# the node runs with the configurations of the chart: it annotates itself
# (kubelet.conf). Right after the join kubelet goes through the VIP: it
# starts the haproxy static pod and registers the node first, about 5 minutes
# as the kubeadm timeouts. The annotations save the first pass of the reconcile
# its work only: without them it applies the configurations again
annotate_applied() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/kubelet.conf")
  local n=1
  until "${kubectl[@]}" annotate node --overwrite "${NODE_NAME}" "$@"; do
    if [ "$n" -ge 150 ]; then
      echo "WARNING: the node isn't annotated, the reconcile applies the configurations again" >&2
      return 0
    fi
    n=$((n + 1))
    sleep 2
  done
}
{{- end -}}
{{- $_ := set $symbols "annotate_applied" (dict
"body" (include "__annotate_applied" $envAll)
) -}}

{{- $_ := set $symbols "annotate_applied_configs" (dict "needs" (list "annotate_applied" "annotations" "kubeadm_config_sha256" "kubelet_config_sha256")
"body" `
# the kubeadm configuration on the control plane nodes too
annotate_applied_configs() {
  if [ "${NODE_ROLE}" == "master" ]; then
    annotate_applied "${KUBELET_ANNOTATION}=$(kubelet_config_sha256)" "${KUBEADM_ANNOTATION}=$(kubeadm_config_sha256)"
  else
    annotate_applied "${KUBELET_ANNOTATION}=$(kubelet_config_sha256)"
  fi
}
`) -}}

{{- $_ := set $symbols "annotate_applied_kubelet" (dict "needs" (list "annotate_applied" "annotations" "kubelet_config_sha256")
"body" `
# the first pass of the reconcile doesn't apply the configuration of kubelet
# again (the one of the values, the bundle may leave it to kubeadm)
annotate_applied_kubelet() {
  if [ ! -f "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet_config.yaml" ]; then
    echo "the values have no configuration of kubelet"
    return 0
  fi
  annotate_applied "${KUBELET_ANNOTATION}=$(kubelet_config_sha256)"
}
`) -}}

{{- $_ := set $symbols "kubeadm_values_init_config" (dict "needs" (list "subst_node_env")
"body" `
# the InitConfiguration of the values for the node (init_config.yaml of the
# kubeadm files, with NODE_IP, NODE_NAME...): the document of its kind only,
# without skipPhases (the ones of kubeadm init, the phases are run one by one)
kubeadm_values_init_config() {
  subst_node_env "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" | awk '
    /^---/ { if (keep) printf "%s", doc; doc = ""; keep = 0; skip = 0; next }
    /^[^ #-]/ { skip = /^skipPhases:/ }
    skip { next }
    { doc = doc $0 "\n" }
    /^kind: *InitConfiguration/ { keep = 1 }
    END { if (keep) printf "%s", doc }'
}
`) -}}

{{- $_ := set $symbols "kubeadm_node_config" (dict "needs" (list "kubeadm_values_init_config")
"body" `
# the kubeadm configuration of the node for kubeadm init phase: the
# InitConfiguration of the values for the node (or the one of the node name,
# it isn't always the hostname kubeadm defaults to), the ClusterConfiguration
# and the kubelet configuration
kubeadm_node_config() {
  if [ -f "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" ]; then
    kubeadm_values_init_config
  else
    cat << EOF_CONFIG
apiVersion: $(sed -n 's/^apiVersion: *//p' "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration" | head -n 1)
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${NODE_IP}
nodeRegistration:
  name: ${NODE_NAME}
  criSocket: $(sed -n 's/^ *containerRuntimeEndpoint: *\(.*\)/\1/p' "${ROOTFS}/var/lib/kubelet/config.yaml")
EOF_CONFIG
  fi
  cat << EOF_CONFIG
---
$(cat "${ROOTFS}/etc/kubernetes/kubeadm/ClusterConfiguration")
---
$(cat "${ROOTFS}/var/lib/kubelet/config.yaml")
EOF_CONFIG
}
`) -}}

{{/* the rebootstrap profile only (bootstrap.profiles.rebootstrap), the files
     kubeadm generates when the values have the CAs only (the backups have
     them anyway) */}}
{{- $_ := set $symbols "kubeadm_generated_files" (dict "body" `
# the certificates and the kubeconfigs kubeadm generates from the CAs: the
# control plane ones on the control plane nodes, the kubeconfig of kubelet (its
# client certificates are in /var/lib/kubelet/pki) on all of them
kubeadm_generated_files() {
  if [ "${NODE_ROLE}" == "master" ]; then
    echo /etc/kubernetes/pki/apiserver.crt /etc/kubernetes/pki/apiserver.key
    echo /etc/kubernetes/pki/apiserver-kubelet-client.crt /etc/kubernetes/pki/apiserver-kubelet-client.key
    echo /etc/kubernetes/pki/apiserver-etcd-client.crt /etc/kubernetes/pki/apiserver-etcd-client.key
    echo /etc/kubernetes/pki/front-proxy-client.crt /etc/kubernetes/pki/front-proxy-client.key
    echo /etc/kubernetes/pki/etcd/server.crt /etc/kubernetes/pki/etcd/server.key
    echo /etc/kubernetes/pki/etcd/peer.crt /etc/kubernetes/pki/etcd/peer.key
    echo /etc/kubernetes/pki/etcd/healthcheck-client.crt /etc/kubernetes/pki/etcd/healthcheck-client.key
    echo /etc/kubernetes/admin.conf /etc/kubernetes/super-admin.conf
    echo /etc/kubernetes/controller-manager.conf /etc/kubernetes/scheduler.conf
  fi
  echo /etc/kubernetes/kubelet.conf
}
`) -}}

{{- $_ := set $symbols "kubeadm_backup" (dict "needs" (list "backup_files" "kubeadm_generated_files")
"body" `
# copies the files kubeadm generated and the certificates of kubelet (the
# directory, kubelet-client-current.pem is a link) to the backup $1
kubeadm_backup() {
  backup_files "$1" $(kubeadm_generated_files)
  if [ -d "${ROOTFS}/var/lib/kubelet/pki" ]; then
    mkdir -p "$1/var/lib/kubelet"
    cp -a "${ROOTFS}/var/lib/kubelet/pki" "$1/var/lib/kubelet/"
  fi
}
`) -}}

{{- $_ := set $symbols "kubeadm_restore" (dict "needs" (list "restore_files" "kubeadm_generated_files")
"body" `
# puts the files of the backup $1 back, removes the ones it doesn't have (the
# node didn't have them before)
kubeadm_restore() {
  restore_files "$1" $(kubeadm_generated_files)
  rm -rf "${ROOTFS}/var/lib/kubelet/pki"
  if [ -d "$1/var/lib/kubelet/pki" ]; then
    cp -a "$1/var/lib/kubelet/pki" "${ROOTFS}/var/lib/kubelet/"
  fi
}
`) -}}

{{- $_ := set $symbols "kubeadm_token_config" (dict "body" `
# the configuration of kubeadm (--config) with the bootstrap token of the join
# (KUBEADM_TOKEN) to the file $2: the files of the node don't have it
kubeadm_token_config() {
  sed "s|\${KUBEADM_TOKEN}|${KUBEADM_TOKEN:-}|g" "${ROOTFS}$1" > "$2"
}
`) -}}

{{- define "__kubeadm_run" -}}
{{- $envAll := . -}}
# kubeadm with the arguments of the phase (init by default)
kubeadm_run() {
  local args=() arg dir config=false rc=0
  [ $# -gt 0 ] || set -- init
  dir=$(mktemp -d)
  for arg in "$@"; do
    if [ "${config}" = true ]; then
      kubeadm_token_config "${arg}" "${dir}/config.yaml"
      arg="${dir}/config.yaml"
      config=false
    elif [ "${arg}" = "--config" ]; then
      config=true
    elif [[ "${arg}" == --config=* ]]; then
      kubeadm_token_config "${arg#--config=}" "${dir}/config.yaml"
      arg="--config=${dir}/config.yaml"
    fi
    args+=("${arg}")
  done
  kubeadm ${args[@]+"${args[@]}"} || rc=$?
  rm -rf "${dir}"
  [ "${rc}" -eq 0 ] || return "${rc}"

  # kubeadm writes its kubelet configuration (/var/lib/kubelet/config.yaml):
  # the one of the chart again, as the reconcile does, and the kubeconfig of
  # the control plane endpoint
  if kubelet_sync_rc; then
    systemctl daemon-reload
    systemctl restart kubelet
  fi
}
{{- end -}}
{{- $_ := set $symbols "kubeadm_run" (dict "needs" (list "kubeadm_token_config" "kubelet_sync_rc")
"body" (include "__kubeadm_run" $envAll)
) -}}

{{- define "__kubeadm_init_certs" -}}
{{- $envAll := . -}}
# the certificates and the kubeconfigs kubeadm generated from the old CAs, the
# client certificates of kubelet (it would take the current one): kubeadm
# generates them from the new CAs, as kubeadm init did
kubeadm_init_certs() {
  local file dir super_admin=false
  # kubeadm init generates it on the first control plane node only
  [ -f "${ROOTFS}/etc/kubernetes/super-admin.conf" ] && super_admin=true
  for file in $(kubeadm_generated_files); do
    rm -f "${ROOTFS}${file}"
  done
  rm -f "${ROOTFS}"/var/lib/kubelet/pki/kubelet-client-*.pem
  dir=$(mktemp -d)
  kubeadm_node_config > "${dir}/config.yaml"
  kubeadm init phase certs all --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig admin --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig controller-manager --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig scheduler --config "${dir}/config.yaml"
  kubeadm init phase kubeconfig kubelet --config "${dir}/config.yaml"
  if [ "${super_admin}" == "true" ]; then
    kubeadm init phase kubeconfig super-admin --config "${dir}/config.yaml"
  fi
  rm -rf "${dir}"
  # kubelet goes through the control plane endpoint
  kubelet_kubeconfig_sync_rc || true
}
{{- end -}}
{{- $_ := set $symbols "kubeadm_init_certs" (dict "needs" (list "kubeadm_generated_files" "kubeadm_node_config" "kubelet_kubeconfig_sync_rc")
"body" (include "__kubeadm_init_certs" $envAll)
) -}}

{{- $_ := set $symbols "kubeadm_certs" (dict "needs" (list "kubeadm_init_certs" "kubelet_tls_bootstrap")
"body" `
# what kubeadm generated from the old CAs on the node, from the new ones
kubeadm_certs() {
  if [ "${NODE_ROLE}" == "master" ]; then
    kubeadm_init_certs
  else
    kubelet_tls_bootstrap
  fi
}
`) -}}

{{- define "__kubeadm_cluster_info" -}}
{{- $envAll := . -}}
# the cluster wide objects with the CAs: kubeadm creates cluster-info only (the
# CA of the token discovery of the joining nodes, server side apply keeps the
# signatures of the tokens), the apiserver creates
# extension-apiserver-authentication with its CAs again (the aggregated API
# servers trust it)
kubeadm_cluster_info() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf")
  local kubeconfig
  if kubeconfig=$("${kubectl[@]}" -n kube-public get configmap cluster-info -o jsonpath='{.data.kubeconfig}'); then
    kubeconfig=$(echo "${kubeconfig}" | sed "s|^\( *certificate-authority-data:\).*|\1 $(base64 < "${ROOTFS}/etc/kubernetes/pki/ca.crt" | tr -d '\n')|")
    "${kubectl[@]}" -n kube-public create configmap cluster-info --from-literal=kubeconfig="${kubeconfig}" \
      --dry-run=client -o yaml | "${kubectl[@]}" apply --server-side --force-conflicts -f -
  fi
  "${kubectl[@]}" -n kube-system delete configmap extension-apiserver-authentication --ignore-not-found
}
{{- end -}}
{{- $_ := set $symbols "kubeadm_cluster_info" (dict
"body" (include "__kubeadm_cluster_info" $envAll)
) -}}

{{- $_ := set $symbols "static_pods_stop" (dict "body" `
# the static pods of the control plane: kubelet starts them again with the new
# certificates, etcd of all the control plane nodes at once
static_pods_stop() {
  local component pods pod
  if [ "${NODE_ROLE}" != "master" ]; then
    echo "not a control plane node"
    return 0
  fi
  for component in kube-apiserver kube-controller-manager kube-scheduler etcd; do
    # not in the for list: errexit doesn't see a failure there
    pods=$(crictl pods -q --namespace kube-system --label "component=${component}")
    for pod in ${pods}; do
      # the default RPC timeout of crictl is 2s: stopping a sandbox takes longer
      crictl --timeout 60s stopp "${pod}"
    done
  done
}
`) -}}
