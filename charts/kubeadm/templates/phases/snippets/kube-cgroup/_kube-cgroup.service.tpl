[Unit]
Description=Create and tune cgroup for Kubernetes Pods
Requires=network-online.target
Before=kubelet.service
StartLimitBurst=3
StartLimitIntervalSec=10

[Service]
Type=oneshot
Slice=kube_whitelist.slice
RemainAfterExit=yes
Delegate=yes
ExecStart=/usr/local/sbin/kube-cgroup.sh
Restart=on-failure
RestartSec=5s

[Install]
RequiredBy=kubelet.service