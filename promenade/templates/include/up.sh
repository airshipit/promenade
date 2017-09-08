# Disable overwriting our resolv.conf
#
resolvconf --disable-updates

# Unpack prepared files into place
#
set +x
log
log === Extracting prepared files ===
echo "{{ tarball | b64enc }}" | base64 -d | tar -zxv -C / | tee /etc/promenade-manifest

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

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    {%- for package in config['HostSystem:packages.additional'] | default([]) %}
    {{ package }} \
    {%- endfor %}
    {{ config['HostSystem:packages.required.docker'] }} \
    {{ config['HostSystem:packages.required.socat'] }}


# Start core processes
#
set +x
log
log === Starting Docker and Kubelet ===
set -x
systemctl daemon-reload
systemctl restart docker || true
systemctl enable kubelet
systemctl restart kubelet
