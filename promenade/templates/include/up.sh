# Disable overwriting our resolv.conf
#
if [ -h /etc/resolv.conf ]; then
  log "=== Removing resolv.conf symlink ==="
  rm -f /etc/resolv.conf
fi

systemctl disable systemd-resolved.service
systemctl stop systemd-resolved.service
systemctl mask systemd-resolved.service

CURATED_DIRS=(
    /etc/kubernetes
    /var/lib/etcd
)

APT_INSTALL_TIMEOUT=${APT_INSTALL_TIMEOUT:-1800}

for DIR in "${CURATED_DIRS[@]}"; do
    mkdir -p "${DIR}"
    chmod 700 "${DIR}"
done

# Unpack prepared files into place
#
set +x
log
log === Extracting prepared files ===
{{ decrypt_setup_command }}
echo "{{ encrypted_tarball | b64enc }}" | base64 -d | {{ decrypt_command }} | tar -zxv -C / | tee /etc/promenade-manifest
{{ decrypt_teardown_command }}
set -x

# Enabling kubectl bash autocompletion
#
kubectl completion bash > /etc/bash_completion.d/kubectl

for DIR in "${CURATED_DIRS[@]}"; do
    chmod -R go-rwx "${DIR}"
done

# Adding apt repositories
#
set +x
log
log === Adding APT Keys===
set -x
{% for role in roles %}
{%- for key in config.get_path('HostSystem:packages.' + role + '.keys', []) %}
apt-key add - <<"ENDKEY"
{{ key }}
ENDKEY
{%- endfor %}
{%- endfor %}

# Disable swap
#
set +x
log
log === Disabling swap ===
set -x
swapoff -a
sed --in-place '/\bswap\b/d' /etc/fstab

# Set proxy variables
#
set +x
log
log === Setting proxy variables ===
set -x
export http_proxy={{ config['KubernetesNetwork:proxy.url'] | default('', true) }}
export https_proxy={{ config['KubernetesNetwork:proxy.url'] | default('', true) }}
export no_proxy={{ config.get(kind='KubernetesNetwork') | fill_no_proxy }}


# Install system packages
#
set +x
log
log === Installing system packages ===
set -x

end=$(($(date +%s) + APT_INSTALL_TIMEOUT))
while true; do
    if ! apt-get update 2>&1 | grep -q '^W: Failed to fetch'; then
        break
    else
        now=$(date +%s)
        if [[ ${now} -gt ${end} ]]; then
            log "Failed to update apt-cache."
            exit 1
        fi
        log "re-try apt-get update..."
        sleep 10
    fi
done

while true; do
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -o Dpkg::Options::="--force-confold" -y --no-install-recommends \
      {%- for role in roles %}
        {%- for package in config.get_path('HostSystem:packages.' + role + '.required',{}).values() %}
        {{ package }} \
        {%- endfor %}
        {%- for package in config.get_path('HostSystem:packages.' + role + '.additional',[]) %}
        {{ package }} \
        {%- endfor %}
      {%- endfor %}
    ;then
        now=$(date +%s)
        if [[ ${now} -gt ${end} ]]; then
            log Failed to install apt packages.
            exit 1
        fi
        sleep 10
    else
        break
    fi
done

# Start core processes
#
set +x
log
log === Starting Docker and Kubelet ===
set -x
systemctl daemon-reload

{% for a in ['enable','start','stop','disable'] %}
{% for u in config.get_units_by_action(a) %}
systemctl {{ a }} {{ u }}
{% endfor %}
{% endfor %}

if systemctl -q is-enabled docker > /dev/null 2>&1; then
  systemctl restart docker || true
fi
if systemctl -q is-enabled containerd > /dev/null 2>&1; then
  systemctl restart containerd || true
fi
systemctl enable kubelet
systemctl restart kubelet
