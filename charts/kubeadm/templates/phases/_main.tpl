{{- $envAll := . -}}
{{- $k8sConfDict := dict -}}
{{/* populates k8sConfDict TODO: rename to phasesConfDict? when we finish */}}

{{/* FS */}}
{{- $allNodes := get $k8sConfDict "allNodes" | default (dict) -}}
{{- $_ := set $k8sConfDict "allNodes" $allNodes -}}
{{- $controlPlaneNodes := get $k8sConfDict "controlPlaneNodes" | default (dict) -}}
{{- $_ := set $k8sConfDict "controlPlaneNodes" $controlPlaneNodes -}}
{{- $perNode := get $k8sConfDict "perNode" | default (dict) -}}
{{- $_ := set $k8sConfDict "perNode" $perNode -}}

{{/* shared script helpers (will go to all scripts)*/}}
{{- $sharedLibs := get $k8sConfDict "sharedLibs" | default (dict) -}}
{{- $_ := set $k8sConfDict "sharedLibs" $sharedLibs -}}

{{/* we're making an alternative implementation for the phases: e.g.
https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/  */}}

{{- $_ := tuple $envAll "templates/phases/_common.tpl" (tuple $envAll $k8sConfDict "common") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_certs.tpl" (tuple $envAll $k8sConfDict "certs") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_kubeconfig.tpl" (tuple $envAll $k8sConfDict "kubeconfig") | include "kubeadm.bundle.template" -}}
{{/* kubelet needs certs and kubeconfig generator to create everything */}}
{{- $_ := tuple $envAll "templates/phases/_kubelet.tpl" (tuple $envAll $k8sConfDict "kubelet") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_kubeadm.tpl" (tuple $envAll $k8sConfDict "kubeadm") | include "kubeadm.bundle.template" -}}
{{/* use containerd as cri and haproxy as vip */}}
{{- $_ := tuple $envAll "templates/phases/_kube-cgroup.tpl" (tuple $envAll $k8sConfDict "kube-cgroup") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_cri_containerd.tpl" (tuple $envAll $k8sConfDict "cri") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_vip_haproxy.tpl" (tuple $envAll $k8sConfDict "vip") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_k8s_up.tpl" (tuple $envAll $k8sConfDict "k8s_up") | include "kubeadm.bundle.template" -}}

{{/* generate shared part for bash scripts with all phases and put it to our object (they will appear in this order) */}}
{{/*TODO: can be implemented shorter, but there are some more complex plans - so, good enough for now */}}
{{- $_ := set $k8sConfDict "sharedLibsContent" (print
      (get $sharedLibs "common")
      (get $sharedLibs "certs")
      (get $sharedLibs "kubeconfig")
      (get $sharedLibs "kubelet")
      (get $sharedLibs "kubeadm")
      (get $sharedLibs "k8s_up")
      (get $sharedLibs "kube-cgroup")
      (get $sharedLibs "cri")
      (get $sharedLibs "vip")
) -}}
{{/* some of the phases also export parts for arg parsing *_cmd. collect all of them */}}
{{- $cmdHookContent := "" -}}
{{- range $name,$content := $sharedLibs -}}
  {{- if hasSuffix "_cmd" $name -}}
    {{- $cmdHookContent = print $cmdHookContent $content -}}
  {{- end -}}
{{- end -}}
{{- $_ := set $k8sConfDict "cmdHookContent" $cmdHookContent -}}

{{/* let's understand if we need perNodeMode based on our situation */}}
{{- $perNode := get $k8sConfDict "perNode" -}}
{{- $perNodeFileCount := 0 -}}
{{- range $nodeName,$nodeFs := $perNode -}}
  {{- $perNodeFileCount = add $perNodeFileCount (len $nodeFs) -}}
{{- end -}}

{{- if eq $perNodeFileCount 0 -}}
{{/* it was empty - use it as a flag that we don't need perNode mode */}}
{{- $_ := unset $k8sConfDict "perNode" -}}
{{- end -}}

{{/* now generate everything with all this data */}}
{{ tuple $envAll "templates/_secret-bootstrap.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}
{{ $nodenameFilter := $envAll.Values.bootstrap.nodename | default "" -}}
{{- if eq $nodenameFilter "" }}
  {{ tuple $envAll "templates/_configmap-bin.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_secret-daemonset-fs.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}

  {{/* TODO:
  this is a WA and
  this is an incorrect way to do this. Helm isn't supposed to own this object
  it will delete it if we delete the chart. Also it will complain if object created by normal kubadm already exists.
  it's necessary to do this using kubectl if it doesn't exist
  */}}
  {{ tuple $envAll "templates/_configmap-for-kubeadm.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}

  {{/* those 2 support patching (because of that it's necesary to add gates and --- here)  */}}
  {{- if $envAll.Values.manifests.daemonset_masters }}
---
    {{ $patch := dict -}}
    {{- if hasKey $envAll.Values.bundle.tpl "templates/_daemonset-masters.yaml.patch" -}}
      {{- $patch = tuple $envAll "templates/_daemonset-masters.yaml.patch" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | fromYaml -}}
    {{- end -}}
    {{- $patch | mergeOverwrite (tuple $envAll "templates/_daemonset-masters.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | fromYaml) | toYaml }}
  {{ end -}}

  {{- if $envAll.Values.manifests.daemonset_workers }}
---
    {{ $patch := dict -}}
    {{- if hasKey $envAll.Values.bundle.tpl "templates/_daemonset-workers.yaml.patch" -}}
      {{- $patch = tuple $envAll "templates/_daemonset-workers.yaml.patch" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | fromYaml -}}
    {{- end -}}
    {{ $patch | mergeOverwrite (tuple $envAll "templates/_daemonset-workers.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | fromYaml) | toYaml }}
  {{ end -}}
{{- end -}}
