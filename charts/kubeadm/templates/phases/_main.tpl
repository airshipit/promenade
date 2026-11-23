{{- $envAll := . -}}
{{- $k8sConfDict := dict -}}
{{/* populates k8sConfDict TODO: rename to phasesConfDict? when we finish */}}

{{/* the archives with the files of the chart, see templates/phases/modules/fs/_.sh.tpl:
     all/ctrl: "<group>/<file>" -> file, *-pernode: node -> "<group>/<file>" -> file */}}
{{- $_ := set $k8sConfDict "fs" (dict "all" (dict) "ctrl" (dict) "all-pernode" (dict) "ctrl-pernode" (dict)) -}}

{{/* the functions and the globals of the scripts, see templates/lib/_linker.tpl */}}
{{- $_ := set $k8sConfDict "symbols" (dict) -}}

{{/* we're making an alternative implementation for the phases: e.g.
https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/  */}}

{{/* the runner of the phases, then the modules (templates/phases/_modules.tpl) */}}
{{- $_ := tuple $envAll "templates/phases/_phase_runner.tpl" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" -}}
{{- $_ := tuple $envAll "templates/phases/_modules.tpl" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" -}}


{{/* the nodes with their own files get their own bootstrap scripts */}}
{{- $perNode := dict -}}
{{- range $archive := list "all-pernode" "ctrl-pernode" -}}
  {{- range $nodeName,$nodeFs := get (get $k8sConfDict "fs") $archive -}}
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
  {{/* for a parent cluster: the CA and the admin client certificate as tls Secrets */}}
  {{ tuple $envAll "templates/_secret-ca-tls.yaml" | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_secret-admin-tls.yaml" | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_cert-manager-admin.yaml" | include "kubeadm.bundle.template" }}

  {{/* those 2 support patching: bundle.tpl."<template>.patch" (strategic merge patch) */}}
  {{- if $envAll.Values.manifests.daemonset_masters }}
---
{{ tuple $envAll "templates/_daemonset-masters.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}

  {{- if $envAll.Values.manifests.daemonset_workers }}
---
{{ tuple $envAll "templates/_daemonset-workers.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}

  {{- if $envAll.Values.manifests.helm_test }}
---
{{ tuple $envAll "templates/_pod-test.yaml" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}
{{- end -}}
