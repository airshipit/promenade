{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# the functions installing the binaries: binaries.sync of the values

{{ tpl $envAll.Values.binaries.sync.kubernetes.body $envAll }}

{{ tpl $envAll.Values.binaries.sync.cri.body $envAll }}

{{ tpl $envAll.Values.binaries.sync.etcd.body $envAll }}

#!define: binary_arch
{{- /* Helpers for binary_kubernetes_sync_rc, binary_cri_sync_rc and
     binary_etcd_sync_rc (above): the #!needs: of binaries.sync of the values
     name the ones they use */}}
# the architecture of the node in the names of the downloads
binary_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    *) echo "unsupported architecture $(uname -m)" >&2; exit 1 ;;
  esac
}

#!define: binary_download
# downloads $2 to $1 and verifies it with the sha256 $3 (with $2.sha256 if
# it's empty), exits on errors
binary_download() {
  local sum="${3:-}"
  [ -n "${sum}" ] || sum=$(curl -fsSL --retry 5 "$2.sha256") || exit 1
  curl -fsSL --retry 5 -o "$1" "$2" && echo "${sum}  $1" | sha256sum -c --quiet - || { rm -f "$1"; exit 1; }
}

#!define: binary_replace
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

#!define: binaries_sync
#!needs: binary_kubernetes_sync_rc
# the given binaries, kubeadm, kubectl and kubelet without arguments
binaries_sync() {
  local name
  [ $# -gt 0 ] || set -- kubeadm kubectl kubelet
  for name in "$@"; do
    binary_kubernetes_sync_rc "$name" || true
  done
}

#!define: cri_setup
#!needs: binary_cri_sync_rc, cri_sync_rc, cri_restart
{{- /* cri_sync_rc and cri_restart: templates/phases/modules/cri/_.sh.tpl */}}
# the container runtime and its configuration, restarted if they are changed
cri_setup() {
  local cri_changed=false
  binary_cri_sync_rc && cri_changed=true
  cri_sync_rc && cri_changed=true
  if [[ $cri_changed == true ]]; then
    cri_restart
  fi
}
