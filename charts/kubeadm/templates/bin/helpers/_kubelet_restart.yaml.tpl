apiVersion: batch/v1
kind: Job
metadata:
  generateName: kubelet-restart-$NODE_NAME-
  labels:
    "kubelet-restart": "true"
spec:
  ttlSecondsAfterFinished: 60
  template:
    metadata:
      labels:
        "kubelet-restart": "true"
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
            appArmorProfile:
              type: RuntimeDefault
          command:
            - nsenter
            - '--target'
            - '1'
            - '--mount'
            - '--uts'
            - '--ipc'
            - '--net'
            - '--pid'
            - --
            - /bin/bash
            - -c
            - |
              set -xeuo pipefail

              echo "perform daemon-reload"
              systemctl daemon-reload
{{- if .Values.kubelet.restart }}
              echo "restarting kubelet service"
              systemctl restart kubelet.service
{{- end }}
              while ! systemctl is-active --quiet kubelet.service; do
                sleep 5
              done

              exit 0
