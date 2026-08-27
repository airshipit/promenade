{{- $envAll := index . 0 -}}
{{- $path := index . 1 -}}
{{- $prefix := index . 2 -}}
{{- $result := "" -}}
{{- dig $path "prefixes" $prefix "mode" "" $envAll.Values.permissions -}}