set +x
log
log === Restarting kubelet ===
set -x
systemctl restart kubelet
