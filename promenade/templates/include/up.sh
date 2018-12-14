# Disable overwriting our resolv.conf
#
resolvconf --disable-updates

CURATED_DIRS=(
    /etc/kubernetes
    /var/lib/etcd
)

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

for DIR in "${CURATED_DIRS[@]}"; do
    chmod -R go-rwx "${DIR}"
done

# Adding apt repositories
#
set +x
log
log === Adding APT Keys===
set -x
{%- for key in config.get_path('HostSystem:packages.keys', []) %}
apt-key add - <<"ENDKEY"
{{ key }}
ENDKEY
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

end=$(($(date +%s) + 600))
while true; do
    if ! apt-get update; then
        now=$(date +%s)
        if [[ ${now} -gt ${end} ]]; then
            log Failed to update apt-cache.
            exit 1
        fi
        sleep 10
    else
        break
    fi
done

end=$(($(date +%s) + 600))
while true; do
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            {%- for package in config['HostSystem:packages.additional'] | default([]) %}
            {{ package }} \
            {%- endfor %}
            {{ config['HostSystem:packages.required.docker'] }} \
            {{ config['HostSystem:packages.required.socat'] }}; then
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

systemctl restart docker || true
systemctl enable kubelet
systemctl restart kubelet
