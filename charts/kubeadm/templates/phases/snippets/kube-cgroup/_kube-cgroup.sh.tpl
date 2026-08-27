!/bin/bash
set -x
mkdir -p /sys/fs/cgroup/kube_whitelist
echo "+cpu +memory +pids" > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null || true
echo "+cpu +memory +pids" > /sys/fs/cgroup/kube_whitelist/cgroup.subtree_control 2>/dev/null || true