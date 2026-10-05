global
{{- range .Values.haproxy.conf_parts.global }}
    {{ . }}
{{- end }}

stats socket /tmp/haproxy.sock mode 700 level admin expose-fd listeners

defaults
{{- range .Values.haproxy.conf_parts.defaults }}
    {{ . }}
{{- end }}