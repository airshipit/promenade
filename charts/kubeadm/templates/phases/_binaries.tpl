{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{- define "__binaries_lib_functions" -}}
{{- $envAll := . -}}
{{- $version := ($envAll.Values.cluster_config).kubernetesVersion | default "" }}
BINARIES_DIR={{ $envAll.Values.binaries.install_dir | quote }}

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

{{ tuple $envAll "templates/phases/snippets/binaries/_helpers.sh.tpl" | include "kubeadm.bundle.template" }}

{{ tuple $envAll "templates/phases/snippets/binaries/_install.sh.tpl" | include "kubeadm.bundle.template" }}

# returns 0 if the binary was changed, 1 if not, exits on errors
sync_binary() {
  local rc=0
  install_binary "$1" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "Failed to install $1" >&2
    exit "$rc"
  fi
  return "$rc"
}

# returns 0 if any of the binaries was changed
sync_binaries() {
  local changed=1 name
  for name in "$@"; do
    sync_binary "$name" && changed=0
  done
  return "$changed"
}
{{- end -}}

{{- $_ := set $sharedLibs $sharedLibName (include "__binaries_lib_functions" $envAll) -}}
