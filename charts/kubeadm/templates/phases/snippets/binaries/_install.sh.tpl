# Installs the binary $1 into ${ROOTFS}${BINARIES_DIR} from binary_source.
# Runs on the node: by the bootstrap script and by the reconcile script on the
# host, so it can use the tools of the node.
# Returns 0 if the binary was changed, 1 if not, >1 on errors.
install_binary() {
  local name="$1" url sha256 tmp rc=0
  IFS='|' read -r url sha256 <<< "$(binary_source "$name")"
  if [ -z "${url}" ]; then
    echo "WARNING: ${name} isn't managed (cluster_config.kubernetesVersion isn't set), the one on the node is used" >&2
    return 1
  fi
  ARCH="${ARCH:-$(node_arch)}" || return 2
  url="${url//\$\{ARCH\}/$ARCH}"

  tmp=$(binary_tmp "${name}") || return 2
  if ! download_verified "${tmp}" "${url}" "${sha256}"; then
    rm -f "${tmp}"
    return 2
  fi
  replace_binary "${tmp}" "${name}" || return $?
  echo "${name} is installed from ${url}"
}