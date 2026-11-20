# Helpers for binary_sync_rc, cri_install_sync_rc (and their overrides): they
# exit on errors.

node_arch() {
  case "$(uname -m)" in
    x86_64) echo amd64 ;;
    aarch64) echo arm64 ;;
    ppc64le) echo ppc64le ;;
    s390x) echo s390x ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
}

# downloads the url $2 to $1, verifies it with the sha512 $4 or the sha256 $3,
# with <url>.sha256 if both are empty; removes $1 on errors
download_verified() {
  local dst="$1" url="$2" sha256="${3:-}" sha512="${4:-}" algo=sha256 sum
  curl -fsSL --retry 5 -o "${dst}" "${url}" || { rm -f "${dst}"; exit 1; }
  if [ -n "${sha512}" ]; then
    algo=sha512 sum="${sha512}"
  elif [ -n "${sha256}" ]; then
    sum="${sha256}"
  else
    sum=$(curl -fsSL --retry 5 "${url}.sha256") || { rm -f "${dst}"; exit 1; }
  fi
  if ! echo "${sum}  ${dst}" | "${algo}sum" -c --quiet -; then
    echo "Checksum mismatch: ${url}" >&2
    rm -f "${dst}"
    exit 1
  fi
}

# prints a temporary file for the binary $1, in its directory for an atomic
# replacement
binary_tmp() {
  mkdir -p "${ROOTFS}{{ .Values.binaries.install_dir }}" && mktemp "${ROOTFS}{{ .Values.binaries.install_dir }}/$1.XXXXXX"
}

# replaces the binary $2 with the file $1 if they differ, removes $1
# returns 0 if the binary was changed, 1 if not
replace_binary() {
  local tmp="$1" dst="${ROOTFS}{{ .Values.binaries.install_dir }}/$2"
  if [ -e "${dst}" ] && cmp -s "${tmp}" "${dst}"; then
    rm -f "${tmp}"
    return 1
  fi
  chmod 0755 "${tmp}" && mv -f "${tmp}" "${dst}" || { rm -f "${tmp}"; exit 1; }
}
