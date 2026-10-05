{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict "allNodes" -}}
{{- $controlPlaneNodes := get $k8sConfDict "controlPlaneNodes" -}}

{{- $foler2prefix:= dict
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
      {{- if not (hasKey $foler2prefix $fdir) -}}{{ fail (printf "_kubeadm.tpl doesn't know how to treat files in %s (filename %s)" $fdir $filename) }}{{- end -}}
      {{- $ftuple := get $foler2prefix $fdir -}}
      {{- $_ := set (index $ftuple 1) (printf "%s%s" (index $ftuple 0) $fname) (dict "content" (tuple $envAll $template | include "kubeadm.bundle.template") "dest_path" "/etc/kubernetes/kubeadm/cluster_config.yaml") -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}
{{- $_ := set $sharedLibs $sharedLibName (printf `
sync_kubeadm() {
  local kubernetes_dir="${HOST_DIR}/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm" "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${kubernetes_dir}/kubeadm" "kubeadm_" "${NODE_ROLE}" true "%s" "%s"
  # init config must include Clusterconfig
  if [ -f "${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml" ]; then
    echo "---" >> ${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml
    cat ${ROOTFS}${kubernetes_dir}/kubeadm/ClusterConfiguration >> ${ROOTFS}${kubernetes_dir}/kubeadm/init_config.yaml
  fi

  #envsubst < $1/tmp/etc/kubernetes/kubeadm/init-config.yaml | compare_copy_file - "${kubernetes_dir}/kubeadm/init_config.yaml"
  #envsubst < $1/tmp/etc/kubernetes/kubeadm/join-config.yaml | compare_copy_file - "${kubernetes_dir}/kubeadm/join_config.yaml"
  #envsubst < $1/tmp/etc/kubernetes/kubeadm/upgrade-config.yaml | compare_copy_file - "${kubernetes_dir}/kubeadm/upgrade_config.yaml"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm/patches" "%s" "%s"
  sync_prefix_based_dir "${ROOTFS}" "${kubernetes_dir}/kubeadm/patches" "kubeadmpatch_" "${NODE_ROLE}" false "%s" "%s"

  if [ "$NODE_ROLE" == "master" ]; then
    ensure_dir "${ROOTFS}${kubernetes_dir}/apiserver" "%s" "%s"
    sync_prefix_based_dir "${ROOTFS}" "${kubernetes_dir}/apiserver" "kubeadmapiserver_" "${NODE_ROLE}" false "%s" "%s"
  fi
  echo "kubeadm is synced"
}
`
(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm" "kubeadm_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm" "kubeadm_") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches" "kubeadmpatch_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/patches" "kubeadmpatch_") | include "kubeadm.bundle.template")

(tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/apiserver") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/apiserver") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/apiserver" "kubeadmapiserver_") | include "kubeadm.bundle.template")
(tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/apiserver" "kubeadmapiserver_") | include "kubeadm.bundle.template")

) -}}