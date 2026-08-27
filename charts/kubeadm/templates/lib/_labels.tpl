{{- define "kubeadm.labels" -}}
{{- $envAll := index . 0 -}}
{{- $application := index . 1 -}}
{{- $component := index . 2 -}}
{{- $podValues := $envAll.Values.pod | default dict -}}
{{- $labels := $podValues.labels | default dict -}}
release_group: {{ $envAll.Values.release_group | default $envAll.Release.Name }}
application: {{ $application }}
component: {{ $component }}
{{- if or $labels.include_app_kubernetes_io (not (hasKey $labels "include_app_kubernetes_io")) }}
app.kubernetes.io/name: {{ $application }}
app.kubernetes.io/component: {{ $component }}
app.kubernetes.io/instance: {{ $envAll.Values.release_group | default $envAll.Release.Name }}
{{- end -}}
{{- if $labels }}
{{- if hasKey $labels $component }}
{{ index $podValues "labels" $component | toYaml }}
{{- end -}}
{{- if hasKey $labels "default" }}
{{ $labels.default | toYaml }}
{{- end -}}
{{- end -}}
{{- end }}