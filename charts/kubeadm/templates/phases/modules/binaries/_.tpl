{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{/* Helpers for binary_kubernetes_sync_rc and binary_cri_sync_rc: their needs
     in binaries.sync of the values list the ones they use
     (templates/phases/modules/binaries/_binary_sync_rc.tpl) */}}
{{- $_ := set $symbols "binary_arch" (dict "body" `
# the architecture of the node in the names of the downloads
binary_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
}
`) -}}

{{- $_ := set $symbols "binary_download" (dict "body" `
# downloads $2 to $1 and verifies it with the sha256 $3 (with $2.sha256 if
# it's empty), exits on errors
binary_download() {
  local sum="${3:-}"
  [ -n "${sum}" ] || sum=$(curl -fsSL --retry 5 "$2.sha256") || exit 1
  curl -fsSL --retry 5 -o "$1" "$2" && echo "${sum}  $1" | sha256sum -c --quiet - || { rm -f "$1"; exit 1; }
}
`) -}}

{{- define "__binary_replace" -}}
{{- $envAll := . -}}
# replaces the binary $2 of binaries.install_dir with the file $1 if they
# differ, returns 0 if it was changed and 1 if not
binary_replace() {
  local dst="${ROOTFS}{{ $envAll.Values.binaries.install_dir }}/$2"
  if [ -e "${dst}" ] && cmp -s "$1" "${dst}"; then
    rm -f "$1"
    return 1
  fi
  chmod 0755 "$1" && mv -f "$1" "${dst}" || { rm -f "$1"; exit 1; }
}
{{- end -}}
{{- $_ := set $symbols "binary_replace" (dict "body" (include "__binary_replace" $envAll)) -}}

{{/* binary_sync_rc: templates/phases/modules/binaries/_binary_sync_rc.tpl */}}
{{- $_ := tuple $envAll "templates/phases/modules/binaries/_binary_sync_rc.tpl" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" -}}

{{- $_ := set $symbols "binaries_sync" (dict "needs" (list "binary_kubernetes_sync_rc")
"body" `
# the given binaries, kubeadm, kubectl and kubelet without arguments
binaries_sync() {
  local name
  [ $# -gt 0 ] || set -- kubeadm kubectl kubelet
  for name in "$@"; do
    binary_kubernetes_sync_rc "$name" || true
  done
}
`) -}}

{{/* cri_sync_rc and cri_restart: templates/phases/modules/cri/_.tpl */}}
{{- $_ := set $symbols "cri_setup" (dict "needs" (list "binary_cri_sync_rc" "cri_sync_rc" "cri_restart")
"body" `
# the container runtime and its configuration, restarted if they are changed
cri_setup() {
  local cri_changed=false
  binary_cri_sync_rc && cri_changed=true
  cri_sync_rc && cri_changed=true
  if [[ $cri_changed == true ]]; then
    cri_restart
  fi
}
`) -}}
