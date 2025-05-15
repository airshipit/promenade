---
apiVersion: batch/v1
kind: Job
metadata:
  generateName: kubelet-restart-$NODE_NAME-
  labels:
    "kubelet-restart": "true"
spec:
  template:
    metadata:
      labels:
        "kubelet-restart": "true"
      annotations:
        container.apparmor.security.beta.kubernetes.io/kubelet-restart: runtime/default
    spec:
      restartPolicy: Never
      serviceAccountName: kubeadm
      serviceAccount: kubeadm
      hostNetwork: true
      enableServiceLinks: true
      hostPID: true
      hostIPC: true
      nodeName: $NODE_NAME
      containers:
        - name: kubelet-restart
          image: {{ .Values.images.tags.anchor }}
          imagePullPolicy: Always
          resources:
            limits:
              cpu: '8'
              memory: 8Gi
            requests:
              cpu: 100m
              memory: 64Mi
          securityContext:
            privileged: true
          command:
            - nsenter
            - '--target'
            - '1'
            - '--mount'
            - '--uts'
            - '--ipc'
            - '--net'
            - '--pid'
            - kubelet_restart.sh
