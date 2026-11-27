{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

# This module installs the binaries on the node.
# The specific implementation is defined in binaries.<kind>.sync of the values.

{{ tpl $envAll.Values.binaries.kubernetes.sync $envAll }}

{{ tpl $envAll.Values.binaries.cri.sync $envAll }}

{{ tpl $envAll.Values.binaries.etcd.sync $envAll }}

#!define: binary_arch
# the architecture of the node
binary_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
}

#!define: binary_download
# downloads $2 to $1 and checks it against the sha256 $3, or against
# $2.sha256 if $3 is empty. Exits on errors
binary_download() {
  local sum="${3:-}"
  [ -n "${sum}" ] || sum=$(curl -fsSL --retry 5 "$2.sha256") || exit 1
  curl -fsSL --retry 5 -o "$1" "$2" && echo "${sum}  $1" | sha256sum -c --quiet - || { rm -f "$1"; exit 1; }
}

#!define: binary_replace_rc
# replaces the binary $2 in binaries.install_dir with the file $1 if they
# differ. Returns 0 if it was replaced and 1 if not, $1 is gone in both cases
binary_replace_rc() {
  local dst="${ROOTFS}{{ $envAll.Values.binaries.install_dir }}/$2"
  if [ -e "${dst}" ] && cmp -s "$1" "${dst}"; then
    rm -f "$1"
    return 1
  fi
  chmod 0755 "$1" && mv -f "$1" "${dst}" || { rm -f "$1"; exit 1; }
}

#!define: binaries_sync_rc
#!needs: binary_kubernetes_sync_rc
# syncs the binaries given as arguments (default: kubeadm, kubectl and
# kubelet). Returns 0 if any of them was changed and 1 if not
binaries_sync_rc() {
  local name changed=1
  [ $# -gt 0 ] || set -- kubeadm kubectl kubelet
  for name in "$@"; do
    binary_kubernetes_sync_rc "$name" && changed=0
  done
  return $changed
}
