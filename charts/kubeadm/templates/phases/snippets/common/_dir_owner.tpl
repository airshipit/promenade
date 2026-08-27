{{- $envAll := index . 0 -}}
{{- $path := index . 1 -}}
{{- dig $path "owner" "" $envAll.Values.permissions -}}