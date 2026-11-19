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
{{- $_ := set $symbols "binaries_helpers" (dict "body" (tuple $envAll "templates/phases/snippets/binaries/_helpers.sh.tpl" | include "kubeadm.bundle.template")) -}}

{{- $_ := set $symbols "binary_install" (dict "needs" (list "binary_source" "binaries_helpers")
"body" (tuple $envAll "templates/phases/snippets/binaries/_install.sh.tpl" | include "kubeadm.bundle.template")
) -}}

{{- $_ := set $symbols "cri_install" (dict "needs" (list "binaries_helpers")
"body" (tuple $envAll "templates/phases/snippets/cri/_install.sh.tpl" | include "kubeadm.bundle.template")
) -}}

{{- $_ := set $symbols "cri_restart" (dict "body" (tuple $envAll "templates/phases/snippets/cri/_restart.sh.tpl" | include "kubeadm.bundle.template")) -}}

{{- $_ := set $symbols "binary_sync_rc" (dict "needs" (list "binary_install")
"body" `
# returns 0 if the binary was changed, 1 if not, exits on errors
binary_sync_rc() {
  local rc=0
  binary_install "$1" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "Failed to install $1" >&2
    exit "$rc"
  fi
  return "$rc"
}
`) -}}

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

{{- $_ := set $symbols "cri_install_sync_rc" (dict "needs" (list "cri_install")
"body" `
# returns 0 if the container runtime was changed, 1 if not, exits on errors
cri_install_sync_rc() {
  local rc=0
  cri_install || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "Failed to install the container runtime" >&2
    exit "$rc"
  fi
  return "$rc"
}
`) -}}

{{/* cri_sync_rc: the files group cri of the values (templates/phases/_fs.tpl) */}}
{{- if not ($envAll.Values.files | default dict).cri -}}
{{- fail "files.cri: the configuration of the container runtime is required by cri_setup and the reconcile, don't remove it" -}}
{{- end -}}
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
