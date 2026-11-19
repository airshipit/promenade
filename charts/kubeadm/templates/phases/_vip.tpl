{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{/* the VIP of the control plane endpoint: the generic part, the
     implementations are the modules of vip.modules (templates/phases/_vip_<module>.tpl),
     they define vip_<module>_sync (vip_sync calls the one of vip_argname),
     vip_<module>_reconcile (vip_reconcile calls the one the node was
     bootstrapped with), they may set vip_argname and vip_arg from the
     arguments of the bootstrap script */}}
{{- $symbols := get $k8sConfDict "symbols" -}}

{{- define "__vip_arg" -}}
{{- $envAll := . -}}
# the VIP: the implementation (vip_argname) and its argument, the values
# (vip.init_argname, vip.init_val) or the last argument of the bootstrap script
# setting them
vip_argname="{{ $envAll.Values.vip.init_argname | default "" }}"
vip_arg="{{ tpl ($envAll.Values.vip.init_val | default "") $envAll }}"
{{- end -}}
{{- $_ := set $symbols "vip_arg" (dict "body" (include "__vip_arg" $envAll)) -}}

{{- define "__vip_sync" -}}
{{- $envAll := . -}}
# the arguments in VIP_FILE (the reconcile follows the VIP the node was
# bootstrapped with, an empty argument is no VIP), then the VIP of the
# implementation vip_argname
vip_sync() {
  [ -z "${vip_arg}" ] || vip_save
  case "${vip_argname}" in
{{- range $module := $envAll.Values.vip.modules }}
    {{ $module }}) vip_{{ $module }}_sync ;;
{{- end }}
    *) echo "unknown VIP implementation '${vip_argname}' (vip.modules: {{ join " " $envAll.Values.vip.modules }})" >&2; return 1 ;;
  esac
}
{{- end -}}

{{- define "__vip_configured" -}}
{{- $envAll := . -}}
# prints the implementation of the VIP the node was bootstrapped with, fails if
# it has none
vip_configured() {
  local argname=""
  # the nodes bootstrapped before VIP_FILE: the VIP of the values, an empty one
  # isn't saved, the values can set it later
  if [ ! -f "${VIP_FILE}" ]; then
    [ -n "${vip_argname}" ] && [ -n "${vip_arg}" ] || return 1
    vip_save
  fi
  read -r argname < "${VIP_FILE}" || true
  [ -n "${argname}" ] && echo "${argname}"
}
{{- end -}}

{{- define "__vip_reconcile" -}}
{{- $envAll := . -}}
# called by the reconcile loop: the VIP the node was bootstrapped with follows
# the control plane endpoints, nothing if it has none. The implementation gets
# the arguments of VIP_FILE in vip_argname and vip_arg
vip_reconcile() {
  local argname
  argname=$(vip_configured) || return 0
  { read -r vip_argname; read -r vip_arg; } < "${VIP_FILE}" || true
  case "${argname}" in
{{- range $module := $envAll.Values.vip.modules }}
    {{ $module }}) vip_{{ $module }}_reconcile ;;
{{- end }}
    *) echo "the node was bootstrapped with the VIP '${argname}', not in vip.modules ({{ join " " $envAll.Values.vip.modules }})" >&2; return 1 ;;
  esac
}
{{- end -}}

{{- $_ := set $symbols "VIP_FILE" (dict "body" `
# the VIP of the bootstrap: the implementation and its argument
VIP_FILE="${ROOTFS}/etc/kubernetes/kubeadm/addons/vip"
`) -}}

{{- define "__vip_save" -}}
{{- $envAll := . -}}
{{- $addonsDirMode := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_mode" -}}
{{- $addonsDirOwner := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_owner" -}}
# the VIP (vip_argname, vip_arg) to VIP_FILE
vip_save() {
  ensure_dir "${VIP_FILE%/*}" "{{ $addonsDirMode }}" "{{ $addonsDirOwner }}"
  printf '%s\n%s\n' "${vip_argname}" "${vip_arg}" > "${VIP_FILE}"
}
{{- end -}}
{{- $_ := set $symbols "vip_save" (dict "needs" (list "ensure_dir" "vip_arg" "VIP_FILE")
"body" (include "__vip_save" $envAll)
) -}}

{{- $sync := list "vip_save" -}}
{{- $configured := list "VIP_FILE" "vip_save" -}}
{{- $reconcile := list "VIP_FILE" "vip_arg" "vip_configured" -}}
{{- range $module := $envAll.Values.vip.modules -}}
  {{- $sync = append $sync (printf "vip_%s_sync" $module) -}}
  {{- $reconcile = append $reconcile (printf "vip_%s_reconcile" $module) -}}
{{- end -}}
{{- $_ := set $symbols "vip_sync" (dict "needs" $sync
"body" (include "__vip_sync" $envAll)
) -}}

{{- $_ := set $symbols "vip_configured" (dict "needs" $configured
"body" (include "__vip_configured" $envAll)
) -}}

{{- $_ := set $symbols "vip_reconcile" (dict "needs" $reconcile
"body" (include "__vip_reconcile" $envAll)
) -}}

{{- define "__vip_check" -}}
{{- $envAll := . -}}
# reconcile: the first pass of the VIP reconcile (vip_reconcile), the
# reconcile loop repeats it after the anchor is ready and ignores its errors
vip_check() {
{{- if $envAll.Values.vip.reconcile }}
  local argname
  if ! argname=$(vip_configured); then
    check_result SKIP vip "the node has no VIP"
  elif vip_reconcile; then
    check_result OK vip "the ${argname} VIP follows the apiservers"
  else
    check_result FAIL vip "the ${argname} VIP can't follow the apiservers (see above)"
  fi
{{- else }}
  check_result SKIP vip "vip.reconcile is disabled"
{{- end }}
  return 0
}
{{- end -}}
{{- $vipCheckNeeds := list "check_result" -}}
{{- if $envAll.Values.vip.reconcile -}}
{{-   $vipCheckNeeds = concat $vipCheckNeeds (list "vip_configured" "vip_reconcile") -}}
{{- end -}}
{{- $_ := set $symbols "vip_check" (dict "needs" $vipCheckNeeds
"body" (include "__vip_check" $envAll)
) -}}

{{/* the implementations */}}
{{- range $module := $envAll.Values.vip.modules -}}
{{- $_ := tuple $envAll (printf "templates/phases/_vip_%s.tpl" $module) (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" -}}
{{- end -}}
