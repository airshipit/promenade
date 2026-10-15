{{- $envAll := index . 0 -}}
{{- $path := index . 1 -}}
{{- $group := index . 2 -}}
{{- $result := "" -}}
{{- dig $path "groups" $group "owner" "" $envAll.Values.permissions -}}