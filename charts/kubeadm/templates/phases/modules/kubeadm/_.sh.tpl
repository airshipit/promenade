{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

{{- $allNodes := get (get $mainDict "fs") "all" -}}
{{- $controlPlaneNodes := get (get $mainDict "fs") "ctrl" -}}

{{- $folder2prefix:= dict
      "." (tuple "kubeadm_" $allNodes)
      "patches" (tuple "kubeadmpatch_" $allNodes)
      "/etc/kubernetes/apiserver" (tuple "kubeadmapiserver_" $controlPlaneNodes)
-}}

{{- if $envAll.Values.kubeadm -}}
  {{- if $envAll.Values.kubeadm.templates -}}
    {{- range $filename,$template := $envAll.Values.kubeadm.templates -}}
      {{/* account for different directories. fail if no matching prefix */}}
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

#!define: kubeadm_node_config
#!needs: subst_node_env

# prints the InitConfiguration document of the values with the variables of
# the node substituted, without skipPhases since kubeadm init phase runs the
# phases one by one
_kubeadm_values_init_config() {
  subst_node_env "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" | awk '
    /^---/ { if (keep) printf "%s", doc; doc = ""; keep = 0; skip = 0; next }
    /^[^ #-]/ { skip = /^skipPhases:/ }
    skip { next }
    { doc = doc $0 "\n" }
    /^kind: *InitConfiguration/ { keep = 1 }
    END { if (keep) printf "%s", doc }'
}

# prints the kubeadm configuration of the node for kubeadm init phase: the
# InitConfiguration of the values, the ClusterConfiguration and the kubelet
# configuration. Without init_config.yaml the InitConfiguration sets the node
# name, because kubeadm defaults to the hostname
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
# prints the certificates and the kubeconfigs kubeadm generates from the CAs:
# all of them on a control plane node and kubelet.conf on a worker
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
# copies the files kubeadm generated and the certificates of kubelet to the
# backup $1. The kubelet directory is copied as a whole because
# kubelet-client-current.pem is a link
kubeadm_backup() {
  backup_files "$1" $(kubeadm_generated_files)
  if [ -d "${ROOTFS}/var/lib/kubelet/pki" ]; then
    mkdir -p "$1/var/lib/kubelet"
    cp -a "${ROOTFS}/var/lib/kubelet/pki" "$1/var/lib/kubelet/"
  fi
}

#!define: kubeadm_restore
#!needs: restore_files, kubeadm_generated_files
# puts the files of the backup $1 back
kubeadm_restore() {
  restore_files "$1" $(kubeadm_generated_files)
  rm -rf "${ROOTFS}/var/lib/kubelet/pki"
  if [ -d "$1/var/lib/kubelet/pki" ]; then
    cp -a "$1/var/lib/kubelet/pki" "${ROOTFS}/var/lib/kubelet/"
  fi
}

#!define: kubeadm_cleanup_upgrade_backups
# kubeadm upgrade backs up the static pod manifests and the etcd data to
# /etc/kubernetes/tmp before changing them and never removes the backups.
# Removes all of them but the last one of each kind
kubeadm_cleanup_upgrade_backups() {
  local p
  if [ -e "${ROOTFS}/etc/kubernetes/tmp/" ]; then
    for p in kubeadm-backup-etcd kubeadm-backup-manifests; do ls -d "${ROOTFS}/etc/kubernetes/tmp/$p-"* 2>/dev/null | sort | sed '$d' | xargs -r rm -rf || true; done
  fi
}

#!define: kubeadm_run
#!needs: kubelet_sync_rc

# writes the kubeadm configuration $1 with KUBEADM_TOKEN substituted to the
# file $2. The files of the node don't keep the token
_kubeadm_token_config() {
  sed "s|\${KUBEADM_TOKEN}|${KUBEADM_TOKEN:-}|g" "${ROOTFS}$1" > "$2"
}

# runs kubeadm with the given arguments (default: init). The --config file
# gets KUBEADM_TOKEN substituted
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

  # kubeadm writes its own kubelet configuration and kubelet.conf, need to
  # re-sync them with the values again
  if kubelet_sync_rc; then
    systemctl daemon-reload
    systemctl restart kubelet
  fi
}

#!define: kubeadm_cluster_info
# updates the CA in the cluster-info ConfigMap, which kubeadm only creates,
# and deletes extension-apiserver-authentication so the apiserver creates it
# again with its CAs. Server side apply keeps the signatures of the bootstrap
# tokens in cluster-info
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
