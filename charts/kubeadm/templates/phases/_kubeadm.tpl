{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict.fs "all" -}}
{{- $controlPlaneNodes := get $k8sConfDict.fs "ctrl" -}}

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