{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

{{- $symbols := get $mainDict "symbols" -}}
{{/* the implementations */}}
{{- range $module := $envAll.Values.vip.modules -}}
{{- $_ := tuple $envAll (printf "templates/phases/modules/vip/_%s.sh.tpl" $module) (tuple $envAll $mainDict) | include "kubeadm.bundle.template" | tuple $symbols | include "linker_symbols_from_sh" -}}
{{- end -}}

# The VIP of the control plane endpoint. An implementation of vip.modules is
# _<module>.sh.tpl, it defines vip_<module>_sync and vip_<module>_reconcile,
# which vip_sync and vip_reconcile call.

#!define: vip_arg
# the implementation of the VIP and its argument, from vip.init_argname and
# vip.init_val unless vip_sync gets others
vip_argname="{{ $envAll.Values.vip.init_argname | default "" }}"
vip_arg="{{ tpl ($envAll.Values.vip.init_val | default "") $envAll }}"

#!define: VIP_FILE
# the implementation and the argument of the VIP the node was bootstrapped with
VIP_FILE="${ROOTFS}/etc/kubernetes/kubeadm/addons/vip"

#!define: vip_save
#!needs: ensure_dir, vip_arg, VIP_FILE
{{- $addonsDirMode := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_mode" }}
{{- $addonsDirOwner := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_owner" }}
# saves vip_argname and vip_arg to VIP_FILE
vip_save() {
  ensure_dir "${VIP_FILE%/*}" "{{ $addonsDirMode }}" "{{ $addonsDirOwner }}"
  printf '%s\n%s\n' "${vip_argname}" "${vip_arg}" > "${VIP_FILE}"
}

#!define: vip_sync
#!needs: vip_save
{{- range $module := $envAll.Values.vip.modules }}
#!needs: vip_{{ $module }}_sync
{{- end }}
# syncs the VIP of the implementation vip_argname and saves it to VIP_FILE,
# a VIP with an empty argument isn't saved. The arguments
# "<implementation> <argument>" replace the ones of the values
vip_sync() {
  [ $# -eq 0 ] || { vip_argname="$1"; vip_arg="${2:-}"; }
  [ -z "${vip_arg}" ] || vip_save
  case "${vip_argname}" in
{{- range $module := $envAll.Values.vip.modules }}
    {{ $module }}) vip_{{ $module }}_sync ;;
{{- end }}
    *) echo "unknown VIP implementation '${vip_argname}' (vip.modules: {{ join " " $envAll.Values.vip.modules }})" >&2; return 1 ;;
  esac
}

#!define: vip_configured
#!needs: VIP_FILE, vip_save
# prints the implementation of the VIP the node was bootstrapped with, fails if
# it has none
vip_configured() {
  local argname=""
  # a node bootstrapped before VIP_FILE existed gets the VIP of the values, an
  # empty one isn't saved so the values can set it later
  if [ ! -f "${VIP_FILE}" ]; then
    [ -n "${vip_argname}" ] && [ -n "${vip_arg}" ] || return 1
    vip_save
  fi
  read -r argname < "${VIP_FILE}" || true
  [ -n "${argname}" ] && echo "${argname}"
}

#!define: vip_reconcile
#!needs: VIP_FILE, vip_arg, vip_configured
{{- range $module := $envAll.Values.vip.modules }}
#!needs: vip_{{ $module }}_reconcile
{{- end }}
# keeps the VIP the node was bootstrapped with in sync with the control plane
# endpoints, nothing if it has none. The implementation gets the arguments of
# VIP_FILE in vip_argname and vip_arg
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

#!define: vip_check
#!needs: check_result, vip_configured, vip_reconcile
# checks that the VIP of the node follows the apiservers by running
# vip_reconcile once
vip_check() {
  local argname
  if ! argname=$(vip_configured); then
    check_result SKIP vip "the node has no VIP"
  elif vip_reconcile; then
    check_result OK vip "the ${argname} VIP follows the apiservers"
  else
    check_result FAIL vip "the ${argname} VIP can't follow the apiservers (see above)"
  fi
  return 0
}
