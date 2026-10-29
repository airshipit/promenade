{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict.fs "all" -}}
{{- $controlPlaneNodes := get $k8sConfDict.fs "ctrl" -}}

{{- $folder2prefix:= dict
      "." (tuple "kubeadm_" $allNodes)
      "patches" (tuple "kubeadmpatch_" $allNodes)
      "/etc/kubernetes/apiserver" (tuple "kubeadmapiserver_" $controlPlaneNodes)
-}}

{{- if $envAll.Values.kubeadm -}}
  {{- if $envAll.Values.kubeadm.fs -}}
    {{- range $filename,$template := $envAll.Values.kubeadm.fs -}}
      {{/* account for different directories. fail if no matiching prefix */}}
      {{- $fname := base $filename -}}
      {{- $fdir := dir $filename -}}
      {{- if not (hasKey $folder2prefix $fdir) -}}{{ fail (printf "_kubeadm.tpl doesn't know how to treat files in %s (filename %s)" $fdir $filename) }}{{- end -}}
      {{- $ftuple := get $folder2prefix $fdir -}}
      {{- $_ := set (index $ftuple 1) (printf "_%s/%s" (trimSuffix "_" (index $ftuple 0)) $fname) (dict "content" (tuple $envAll $template | include "kubeadm.bundle.template") "dest_path" "/etc/kubernetes/kubeadm/cluster_config.yaml") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $_ := set $sharedLibs $sharedLibName (printf `
sync_kubeadm() {
  local kubernetes_dir="/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm" "%s" "%s"
  sync_group_dir "${ROOTFS}" "_kubeadm" "${kubernetes_dir}/kubeadm" "${NODE_ROLE}" true "%s" "%s"
  # init config must include Clusterconfig
  if [ -f "${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml" ]; then
    echo "---" >> ${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml
    cat ${ROOTFS}${kubernetes_dir}/kubeadm/ClusterConfiguration >> ${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml
  fi

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm/patches" "%s" "%s"
  sync_group_dir "${ROOTFS}" "_kubeadmpatch" "${kubernetes_dir}/kubeadm/patches" "${NODE_ROLE}" false "%s" "%s"

  if [ "$NODE_ROLE" == "master" ]; then
    ensure_dir "${ROOTFS}${kubernetes_dir}/apiserver" "%s" "%s"
    sync_group_dir "${ROOTFS}" "_kubeadmapiserver" "${kubernetes_dir}/apiserver" "${NODE_ROLE}" false "%s" "%s"
  fi
  echo "kubeadm is synced"
}

# the annotations of the node with the configurations it runs with: the
# reconcile script applies the kubeadm (control plane nodes) and the kubelet
# configuration only if the node runs with another one
KUBEADM_ANNOTATION="last-applied-kubeadm-cfg-sha256"
KUBELET_ANNOTATION="last-applied-kubelet-cfg-sha256"

kubeadm_config_sha256() {
  sha256sum < "${ROOTFS}/run/kubeadm/all/_kubeadm/ClusterConfiguration" | cut -d ' ' -f 1
}

kubelet_config_sha256() {
  sha256sum < "${ROOTFS}/run/kubeadm/all/_kubelet/kubelet_config.yaml" | cut -d ' ' -f 1
}

# the node runs with the configurations of the chart: the kubectl of the
# script annotates it. Right after the join kubelet goes through the VIP: it
# starts the haproxy static pod and registers the node first, about 5 minutes
# as the kubeadm timeouts. The annotations save the first pass of the reconcile
# its work only: without them it applies the configurations again
annotate_applied() {
  local n=1
  until kubectl annotate node --overwrite "${NODE_NAME}" "$@"; do
    if [ "$n" -ge 150 ]; then
      echo "WARNING: the node isn't annotated, the reconcile applies the configurations again" >&2
      return 0
    fi
    n=$((n + 1))
    sleep 2
  done
}

# the kubeadm configuration on the control plane nodes too
annotate_applied_configs() {
  if [ "$NODE_ROLE" == "master" ]; then
    annotate_applied "${KUBELET_ANNOTATION}=$(kubelet_config_sha256)" "${KUBEADM_ANNOTATION}=$(kubeadm_config_sha256)"
  else
    annotate_applied "${KUBELET_ANNOTATION}=$(kubelet_config_sha256)"
  fi
}

# the InitConfiguration of the values for the node (init_config.yaml of the
# kubeadm files, with NODE_IP, NODE_NAME...): the document of its kind only,
# without skipPhases (the ones of kubeadm init, the phases are run one by one)
kubeadm_values_init_config() {
  subst_node_env "${ROOTFS}/run/kubeadm/all/_kubeadm/init_config.yaml" | awk '
    /^---/ { if (keep) printf "%%s", doc; doc = ""; keep = 0; skip = 0; next }
    /^[^ #-]/ { skip = /^skipPhases:/ }
    skip { next }
    { doc = doc $0 "\n" }
    /^kind: *InitConfiguration/ { keep = 1 }
    END { if (keep) printf "%%s", doc }'
}

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
`
(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm" "kubeadm") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm" "kubeadm") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches" "kubeadmpatch") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches" "kubeadmpatch") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/apiserver") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/apiserver") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/apiserver" "kubeadmapiserver") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/apiserver" "kubeadmapiserver") | include "kubeadm.bundle.template")

) -}}

{{/* kubeadm_rebootstrap_lib: the functions of the rebootstrap script
     (templates/bin/_rebootstrap.tpl), the files kubeadm generates when the
     values have the CAs only (the backups have them anyway) */}}
{{- $_ := set $sharedLibs (printf "%s_rebootstrap_lib" $sharedLibName) `
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

# copies the files kubeadm generated and the certificates of kubelet (the
# directory, kubelet-client-current.pem is a link) to the backup $1
kubeadm_backup() {
  backup_files "$1" $(kubeadm_generated_files)
  if [ -d "${ROOTFS}/var/lib/kubelet/pki" ]; then
    mkdir -p "$1/var/lib/kubelet"
    cp -a "${ROOTFS}/var/lib/kubelet/pki" "$1/var/lib/kubelet/"
  fi
}

# puts the files of the backup $1 back, removes the ones it doesn't have (the
# node didn't have them before)
kubeadm_restore() {
  restore_files "$1" $(kubeadm_generated_files)
  rm -rf "${ROOTFS}/var/lib/kubelet/pki"
  if [ -d "$1/var/lib/kubelet/pki" ]; then
    cp -a "$1/var/lib/kubelet/pki" "${ROOTFS}/var/lib/kubelet/"
  fi
}
` -}}