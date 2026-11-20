# Installs the binary $1 into ${ROOTFS}{{ .Values.binaries.install_dir }} from binary_source.
# Runs on the node: by the bootstrap script and by the reconcile script on the
# host, so it can use the tools of the node.
# Returns 0 if the binary was changed, 1 if not, exits on errors.
binary_sync_rc() {
  local name="$1" url sha256 tmp
  IFS='|' read -r url sha256 <<< "$(binary_source "$name")"
  if [ -z "${url}" ]; then
    echo "WARNING: ${name} isn't managed (cluster_config.kubernetesVersion isn't set), the one on the node is used" >&2
    return 1
  fi
  ARCH="${ARCH:-$(node_arch)}" || exit 1
  url="${url//\$\{ARCH\}/$ARCH}"

  tmp=$(binary_tmp "${name}") || exit 1
  download_verified "${tmp}" "${url}" "${sha256}"
  replace_binary "${tmp}" "${name}" || return 1
  echo "${name} is installed from ${url}"
}