{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{/* we put here some common code which is used by most of the modules */}}
{{- $_ := set $sharedLibs $sharedLibName `
k8s_up() {
  # turn off swap
  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' "${ROOTFS}${HOST_DIR}/etc/fstab"

  # Configure kernel modules and sysctl for net bridge (Containerd/Docker)
  cat <<EOF | sudo tee "${ROOTFS}${HOST_DIR}/etc/modules-load.d/k8s.conf"
overlay
br_netfilter
EOF

  sudo modprobe overlay || true
  sudo modprobe br_netfilter || true

  cat <<EOF | sudo tee "${ROOTFS}${HOST_DIR}/etc/sysctl.d/k8s.conf"
net.bridge.bridge-netfilter-call-iptables  = 1
net.bridge.bridge-netfilter-call-ip6tables = 1
net.ipv4.ip_forward                        = 1
EOF

  sudo sysctl --system
}
` -}}
