{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{- define "__binary_source" -}}
{{- $envAll := . -}}
{{- $version := ($envAll.Values.cluster_config).kubernetesVersion | default "" -}}
# prints "url|sha256" of the binary, nothing if it isn't managed
binary_source() {
  case "$1" in
{{- if $version }}
{{- range $name := list "kubeadm" "kubelet" "kubectl" }}
{{- $binary := index $envAll.Values.binaries $name }}
    {{ $name }}) echo {{ printf "%s|%s" (tpl $binary.url $envAll) ($binary.sha256 | default "") | squote }} ;;
{{- end }}
{{- end }}
  esac
}
{{- end -}}
{{- $_ := set $symbols "binary_source" (dict "body" (include "__binary_source" $envAll)) -}}

{{/* the snippets of bundle.tpl (the installation procedures of the values):
     a symbol each, they may call the helpers */}}
{{- $_ := set $symbols "binaries_helpers" (dict "body" (tuple $envAll "templates/phases/modules/binaries/_helpers.sh.tpl" | include "kubeadm.bundle.template")) -}}

{{- $_ := set $symbols "binary_sync_rc" (dict "needs" (list "binary_source" "binaries_helpers")
"body" (tuple $envAll "templates/phases/modules/binaries/_install.sh.tpl" | include "kubeadm.bundle.template")
) -}}

{{- $_ := set $symbols "cri_install_sync_rc" (dict "needs" (list "binaries_helpers")
"body" (tuple $envAll "templates/phases/modules/cri/_install.sh.tpl" | include "kubeadm.bundle.template")
) -}}

{{- $_ := set $symbols "binaries_sync" (dict "needs" (list "binary_sync_rc")
"body" `
# the given binaries, kubeadm, kubectl and kubelet without arguments
binaries_sync() {
  local name
  [ $# -gt 0 ] || set -- kubeadm kubectl kubelet
  for name in "$@"; do
    binary_sync_rc "$name" || true
  done
}
`) -}}

{{/* cri_sync_rc and cri_restart: templates/phases/modules/cri/_.tpl */}}
{{- $_ := set $symbols "cri_setup" (dict "needs" (list "cri_install_sync_rc" "cri_sync_rc" "cri_restart")
"body" `
# the container runtime and its configuration, restarted if they are changed
cri_setup() {
  local cri_changed=false
  cri_install_sync_rc && cri_changed=true
  cri_sync_rc && cri_changed=true
  if [[ $cri_changed == true ]]; then
    cri_restart
  fi
}
`) -}}
