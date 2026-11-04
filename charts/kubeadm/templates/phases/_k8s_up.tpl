{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{- $_ := set $symbols "k8s_up" (dict "body" `
k8s_up() {
  # turn off swap
  sudo swapoff -a
  sudo sed -i '/ swap / s/^/#/' "${ROOTFS}/etc/fstab"

  # Configure kernel modules and sysctl for net bridge (Containerd/Docker)
  cat <<EOF | sudo tee "${ROOTFS}/etc/modules-load.d/k8s.conf"
overlay
br_netfilter
EOF

  sudo modprobe overlay || true
  sudo modprobe br_netfilter || true

  cat <<EOF | sudo tee "${ROOTFS}/etc/sysctl.d/k8s.conf"
net.bridge.bridge-netfilter-call-iptables  = 1
net.bridge.bridge-netfilter-call-ip6tables = 1
net.ipv4.ip_forward                        = 1
EOF

  sudo sysctl --system
}
`) -}}
