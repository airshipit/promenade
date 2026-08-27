{{- $envAll := index . 0 -}}
{{- $path := index . 1 -}}
{{- dig $path "mode" "" $envAll.Values.permissions -}}