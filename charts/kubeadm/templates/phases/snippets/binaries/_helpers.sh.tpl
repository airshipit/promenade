# Helpers for install_binary (and its overrides).

node_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    ppc64le) echo ppc64le ;;
    s390x) echo s390x ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; return 2 ;;
  esac
}

# downloads the url $2 to $1, verifies it with the sha512 $4 or the sha256 $3,
# with <url>.sha256 if both are empty
download_verified() {
  local dst="$1" url="$2" sha256="${3:-}" sha512="${4:-}" algo=sha256 sum
  curl -fsSL --retry 5 -o "${dst}" "${url}" || return 2
  if [ -n "${sha512}" ]; then
    algo=sha512 sum="${sha512}"
  elif [ -n "${sha256}" ]; then
    sum="${sha256}"
  else
    sum=$(curl -fsSL --retry 5 "${url}.sha256") || return 2
  fi
  if ! echo "${sum}  ${dst}" | "${algo}sum" -c --quiet -; then
    echo "Checksum mismatch: ${url}" >&2
    return 2
  fi
}

# prints a temporary file for the binary $1, in its directory for an atomic
# replacement
binary_tmp() {
  mkdir -p "${ROOTFS}${BINARIES_DIR}" && mktemp "${ROOTFS}${BINARIES_DIR}/$1.XXXXXX"
}

# replaces the binary $2 with the file $1 if they differ, removes $1
# returns 0 if the binary was changed, 1 if not, >1 on errors
replace_binary() {
  local tmp="$1" dst="${ROOTFS}${BINARIES_DIR}/$2"
  if [ -e "${dst}" ] && cmp -s "${tmp}" "${dst}"; then
    rm -f "${tmp}"
    return 1
  fi
  if ! chmod 0755 "${tmp}" || ! mv -f "${tmp}" "${dst}"; then
    rm -f "${tmp}"
    return 2
  fi
}
