{{- $envAll := . -}}
{{- $k8sConfDict := dict -}}
{{/* populates k8sConfDict TODO: rename to phasesConfDict? when we finish */}}

{{/* the archives with the files of the chart, see templates/phases/_fs.tpl:
     all/ctrl: "<group>/<file>" -> file, *-pernode: node -> "<group>/<file>" -> file */}}
{{- $_ := set $k8sConfDict "fs" (dict "all" (dict) "ctrl" (dict) "all-pernode" (dict) "ctrl-pernode" (dict)) -}}

{{/* shared script helpers (will go to all scripts)*/}}
{{- $sharedLibs := get $k8sConfDict "sharedLibs" | default (dict) -}}
{{- $_ := set $k8sConfDict "sharedLibs" $sharedLibs -}}

{{/* we're making an alternative implementation for the phases: e.g.
https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/  */}}

{{- $_ := tuple $envAll "templates/phases/_fs.tpl" (tuple $envAll $k8sConfDict "fs") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_certs.tpl" (tuple $envAll $k8sConfDict "certs") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_kubeconfig.tpl" (tuple $envAll $k8sConfDict "kubeconfig") | include "kubeadm.bundle.template" -}}
{{/* kubelet needs certs and kubeconfig generator to create everything */}}
{{- $_ := tuple $envAll "templates/phases/_kubelet.tpl" (tuple $envAll $k8sConfDict "kubelet") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_kubeadm.tpl" (tuple $envAll $k8sConfDict "kubeadm") | include "kubeadm.bundle.template" -}}
{{/* use haproxy as vip */}}
{{- $_ := tuple $envAll "templates/phases/_kube-cgroup.tpl" (tuple $envAll $k8sConfDict "kube-cgroup") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_vip_haproxy.tpl" (tuple $envAll $k8sConfDict "vip") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_k8s_up.tpl" (tuple $envAll $k8sConfDict "k8s_up") | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_binaries.tpl" (tuple $envAll $k8sConfDict "binaries") | include "kubeadm.bundle.template" -}}

{{/* generate shared part for bash scripts with all phases and put it to our object (they will appear in this order) */}}
{{/*TODO: can be implemented shorter, but there are some more complex plans - so, good enough for now */}}
{{- $_ := set $k8sConfDict "sharedLibsContent" (print
      (get $sharedLibs "fs")
      (get $sharedLibs "certs")
      (get $sharedLibs "kubeconfig")
      (get $sharedLibs "kubelet")
      (get $sharedLibs "kubeadm")
      (get $sharedLibs "k8s_up")
      (get $sharedLibs "kube-cgroup")
      (get $sharedLibs "vip")
      (get $sharedLibs "binaries")
) -}}
{{/* some of the phases also export parts for arg parsing *_cmd. collect all of them */}}
{{- $cmdHookContent := "" -}}
{{- range $name,$content := $sharedLibs -}}
  {{- if hasSuffix "_cmd" $name -}}
    {{- $cmdHookContent = print $cmdHookContent $content -}}
  {{- end -}}
{{- end -}}
{{- $_ := set $k8sConfDict "cmdHookContent" $cmdHookContent -}}

{{/* the nodes with their own files get their own bootstrap scripts */}}
{{- $perNode := dict -}}
{{- range $archive := list "all-pernode" "ctrl-pernode" -}}
  {{- range $nodeName,$nodeFs := get $k8sConfDict.fs $archive -}}
    {{- if $nodeFs -}}{{- $_ := set $perNode $nodeName true -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- if $perNode -}}
{{- $_ := set $k8sConfDict "perNode" $perNode -}}
{{- end -}}

{{/* now generate everything with all this data */}}
{{ tuple $envAll "templates/_secret-bootstrap.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}
{{ $nodenameFilter := $envAll.Values.bootstrap.nodename | default "" -}}
{{- if eq $nodenameFilter "" }}
  {{ tuple $envAll "templates/_configmap-bin.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_secret-daemonset-fs.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" }}

  {{/* those 2 support patching: bundle.tpl."<template>.patch" (strategic merge patch) */}}
  {{- if $envAll.Values.manifests.daemonset_masters }}
---
{{ tuple $envAll "templates/_daemonset-masters.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}

  {{- if $envAll.Values.manifests.daemonset_workers }}
---
{{ tuple $envAll "templates/_daemonset-workers.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}
{{- end -}}
