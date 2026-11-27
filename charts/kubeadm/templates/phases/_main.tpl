{{- $envAll := . -}}
{{- $mainDict := dict -}}
{{/* the modules fill mainDict, the templates below render it */}}

{{/* the archives with the files of the chart: all and ctrl map
     "<group>/<file>" to a file, the *-pernode ones map a node to such a map */}}
{{- $_ := set $mainDict "fs" (dict "all" (dict) "ctrl" (dict) "all-pernode" (dict) "ctrl-pernode" (dict)) -}}

{{/* the functions and the globals of the scripts, see the linker */}}
{{- $_ := set $mainDict "symbols" (dict) -}}

{{/* we're making an alternative implementation for the phases: e.g.
https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init/  */}}

{{- $_ := tuple $envAll "templates/phases/_modules.tpl" (tuple $envAll $mainDict) | include "kubeadm.bundle.template" -}}

{{/* the nodes with their own files get their own phase-runner scripts */}}
{{- $perNode := dict -}}
{{- range $archive := list "all-pernode" "ctrl-pernode" -}}
  {{- range $nodeName,$nodeFs := get (get $mainDict "fs") $archive -}}
    {{- if $nodeFs -}}{{- $_ := set $perNode $nodeName true -}}{{- end -}}
  {{- end -}}
{{- end -}}
{{- if $perNode -}}
{{- $_ := set $mainDict "perNode" $perNode -}}
{{- end -}}

{{/* now generate everything with all this data */}}
{{ tuple $envAll "templates/_secret-phase-runner.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.template" }}
{{ $nodenameFilter := $envAll.Values.phase_runner.nodename | default "" -}}
{{- if eq $nodenameFilter "" }}
  {{ tuple $envAll "templates/_configmap-bin.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_secret-daemonset-fs.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.template" }}
  {{/* for a parent cluster: the CA and the admin client certificate as tls Secrets */}}
  {{ tuple $envAll "templates/_secret-ca-tls.yaml" | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_secret-admin-tls.yaml" | include "kubeadm.bundle.template" }}
  {{ tuple $envAll "templates/_cert-manager-admin.yaml" | include "kubeadm.bundle.template" }}

  {{/* these support patching: bundle.tpl."<template>.patch" (strategic merge patch).
       The --- stays here because kubeadm.bundle.patched_template renders them
       again with fromYaml and toYaml, which drops the --- of the file */}}
  {{- if $envAll.Values.manifests.daemonset_masters }}
---
{{ tuple $envAll "templates/_daemonset-masters.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}

  {{- if $envAll.Values.manifests.daemonset_workers }}
---
{{ tuple $envAll "templates/_daemonset-workers.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}

  {{- if $envAll.Values.manifests.helm_test }}
---
{{ tuple $envAll "templates/_pod-test.yaml" (tuple $envAll $mainDict) | include "kubeadm.bundle.patched_template" }}
  {{ end -}}
{{- end -}}
