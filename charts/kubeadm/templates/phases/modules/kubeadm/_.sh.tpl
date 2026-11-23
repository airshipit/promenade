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
      {{- if not (hasKey $folder2prefix $fdir) -}}{{ fail (printf "templates/phases/modules/kubeadm/_.sh.tpl doesn't know how to treat files in %s (filename %s)" $fdir $filename) }}{{- end -}}
      {{- $ftuple := get $folder2prefix $fdir -}}
      {{- $_ := set (index $ftuple 1) (printf "_%s/%s" (trimSuffix "_" (index $ftuple 0)) $fname) (dict "content" (tuple $envAll $template | include "kubeadm.bundle.template") "dest_path" "/etc/kubernetes/kubeadm/cluster_config.yaml") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

#!define: kubeadm_sync
#!needs: ensure_dir, group_dir_sync
{{- $kubernetesKubeadmDirMode := tuple $envAll "/etc/kubernetes/kubeadm" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesKubeadmDirOwner := tuple $envAll "/etc/kubernetes/kubeadm" | include "kubeadm.fs.dir_owner" }}
{{- $kubeadmMode := tuple $envAll "kubeadm" "kubeadm" | include "kubeadm.fs.file_mode" }}
{{- $kubeadmOwner := tuple $envAll "kubeadm" "kubeadm" | include "kubeadm.fs.file_owner" }}
{{- $kubernetesKubeadmPatchesDirMode := tuple $envAll "/etc/kubernetes/kubeadm/patches" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesKubeadmPatchesDirOwner := tuple $envAll "/etc/kubernetes/kubeadm/patches" | include "kubeadm.fs.dir_owner" }}
{{- $kubeadmpatchMode := tuple $envAll "kubeadm" "kubeadmpatch" | include "kubeadm.fs.file_mode" }}
{{- $kubeadmpatchOwner := tuple $envAll "kubeadm" "kubeadmpatch" | include "kubeadm.fs.file_owner" }}
{{- $kubernetesApiserverDirMode := tuple $envAll "/etc/kubernetes/apiserver" | include "kubeadm.fs.dir_mode" }}
{{- $kubernetesApiserverDirOwner := tuple $envAll "/etc/kubernetes/apiserver" | include "kubeadm.fs.dir_owner" }}
{{- $kubeadmapiserverMode := tuple $envAll "kubeadm" "kubeadmapiserver" | include "kubeadm.fs.file_mode" }}
{{- $kubeadmapiserverOwner := tuple $envAll "kubeadm" "kubeadmapiserver" | include "kubeadm.fs.file_owner" }}
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

#!define: _kubeadm_files_sha256
#!needs: _groups_sha256
# the configurations and the patches kubeadm is run with
_kubeadm_files_sha256() {
  _groups_sha256 "${ROOTFS}" "${NODE_ROLE}" _kubeadm _kubeadmpatch
}

#!define: kubeadm_mark_applied
#!needs: node_info_update, node_info_update_wait, _kubeadm_files_sha256
# the control plane node runs with the kubeadm files of the values: the first
# pass of the reconcile doesn't apply them again. Written as the node
# (kubelet.conf) unless KUBECONFIG is set (the reconcile)
kubeadm_mark_applied() {
  if [ "${NODE_ROLE}" != "master" ]; then
    echo "the kubeadm configuration is applied on the control plane nodes only"
    return 0
  fi
  KUBECONFIG="${KUBECONFIG:-${ROOTFS}/etc/kubernetes/kubelet.conf}" node_info_update_wait kubeadm_applied "$(_kubeadm_files_sha256)"
}

#!define: kubeadm_action_required_rc
#!needs: _kubeadm_files_sha256, node_info_field
# 0 if the control plane node doesn't run the kubeadm files of the values
# (kubeadm_mark_applied, the state of the node $1 from node_info_load),
# 1 if it does and on the other nodes
kubeadm_action_required_rc() {
  local applied
  [ "${NODE_ROLE}" == "master" ] || return 1
  applied=$(node_info_field "$1" kubeadm_applied)
  [[ -z $applied || $applied != $(_kubeadm_files_sha256) ]]
}

#!define: kubeadm_node_config
#!needs: subst_node_env

# kubeadm_node_config's helper: the InitConfiguration of the values for the
# node (init_config.yaml of the kubeadm files, with NODE_IP, NODE_NAME...): the
# document of its kind only, without skipPhases (the ones of kubeadm init, the
# phases are run one by one)
_kubeadm_values_init_config() {
  subst_node_env "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" | awk '
    /^---/ { if (keep) printf "%s", doc; doc = ""; keep = 0; skip = 0; next }
    /^[^ #-]/ { skip = /^skipPhases:/ }
    skip { next }
    { doc = doc $0 "\n" }
    /^kind: *InitConfiguration/ { keep = 1 }
    END { if (keep) printf "%s", doc }'
}

# the kubeadm configuration of the node for kubeadm init phase: the
# InitConfiguration of the values for the node (or the one of the node name,
# it isn't always the hostname kubeadm defaults to), the ClusterConfiguration
# and the kubelet configuration
kubeadm_node_config() {
  if [ -f "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" ]; then
    _kubeadm_values_init_config
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

#!define: kubeadm_generated_files
{{- /* the rebootstrap profile only (phase_runner.profiles.rebootstrap), the files
     kubeadm generates when the values have the CAs only (the backups have
     them anyway) */}}
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

#!define: kubeadm_backup
#!needs: backup_files, kubeadm_generated_files
# copies the files kubeadm generated and the certificates of kubelet (the
# directory, kubelet-client-current.pem is a link) to the backup $1
kubeadm_backup() {
  backup_files "$1" $(kubeadm_generated_files)
  if [ -d "${ROOTFS}/var/lib/kubelet/pki" ]; then
    mkdir -p "$1/var/lib/kubelet"
    cp -a "${ROOTFS}/var/lib/kubelet/pki" "$1/var/lib/kubelet/"
  fi
}

#!define: kubeadm_restore
#!needs: restore_files, kubeadm_generated_files
# puts the files of the backup $1 back, removes the ones it doesn't have (the
# node didn't have them before)
kubeadm_restore() {
  restore_files "$1" $(kubeadm_generated_files)
  rm -rf "${ROOTFS}/var/lib/kubelet/pki"
  if [ -d "$1/var/lib/kubelet/pki" ]; then
    cp -a "$1/var/lib/kubelet/pki" "${ROOTFS}/var/lib/kubelet/"
  fi
}

#!define: kubeadm_upgrade_backups_cleanup
# the backups kubeadm upgrade leaves in /etc/kubernetes/tmp, but the last ones
kubeadm_upgrade_backups_cleanup() {
  local p
  if [ -e "${ROOTFS}/etc/kubernetes/tmp/" ]; then
    for p in kubeadm-backup-etcd kubeadm-backup-manifests; do ls -d "${ROOTFS}/etc/kubernetes/tmp/$p-*" 2>/dev/null | sort | sed '$d' | xargs -r rm -rf || true; done
  fi
}

#!define: kubeadm_run
#!needs: kubelet_sync_rc

# kubeadm_run's helper: the configuration of kubeadm (--config) with the
# bootstrap token of the join (KUBEADM_TOKEN) to the file $2, the files of the
# node don't have it
_kubeadm_token_config() {
  sed "s|\${KUBEADM_TOKEN}|${KUBEADM_TOKEN:-}|g" "${ROOTFS}$1" > "$2"
}

# kubeadm with the arguments of the phase (init by default)
kubeadm_run() {
  local args=() arg dir config=false rc=0
  [ $# -gt 0 ] || set -- init
  dir=$(mktemp -d)
  for arg in "$@"; do
    if [ "${config}" = true ]; then
      _kubeadm_token_config "${arg}" "${dir}/config.yaml"
      arg="${dir}/config.yaml"
      config=false
    elif [ "${arg}" = "--config" ]; then
      config=true
    elif [[ "${arg}" == --config=* ]]; then
      _kubeadm_token_config "${arg#--config=}" "${dir}/config.yaml"
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

#!define: kubeadm_cluster_info
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
