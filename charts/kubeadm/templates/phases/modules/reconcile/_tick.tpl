{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}

{{- define "__reconcile_tick" -}}
{{- $envAll := . -}}
# every period of the main loop: fails if a change needs a new pass (the anchor
# restarts), the VIP the node was bootstrapped with follows the control plane
# endpoints meanwhile
reconcile_tick() {
  if is_action_required; then
    return 1
  fi
{{- if dig "reconcile" false ($envAll.Values.vip | default dict) }}
  vip_reconcile || true
{{- end }}
}
{{- end -}}
{{- $needs := list "is_action_required" -}}
{{- if dig "reconcile" false ($envAll.Values.vip | default dict) -}}
  {{- $needs = append $needs "vip_reconcile" -}}
{{- end -}}
{{- $_ := set $symbols "reconcile_tick" (dict "needs" $needs
"body" (include "__reconcile_tick" $envAll)
) -}}
