{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- $sync := $envAll.Values.binaries.sync -}}

{{/* binary_kubernetes_sync_rc <name> installs kubeadm, kubelet or kubectl to
     binaries.install_dir, binary_cri_sync_rc installs the container runtime.
     They return 0 if they changed something, 1 if not, and exit on errors
     (they are called in && and || lists). They come from binaries.sync of the
     values: their bodies are tpl strings, their needs list the helpers of this
     module they use */}}
{{- $_ := set $symbols "binary_kubernetes_sync_rc" (dict "needs" ($sync.kubernetes.needs | default list)
"body" (tpl $sync.kubernetes.body $envAll)
) -}}

{{- $_ := set $symbols "binary_cri_sync_rc" (dict "needs" ($sync.cri.needs | default list)
"body" (tpl $sync.cri.body $envAll)
) -}}
