{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{/* the implementations */}}
{{- range $module := $envAll.Values.vip.modules -}}
{{- $_ := tuple $envAll (printf "templates/phases/modules/vip/_%s.sh.tpl" $module) (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | tuple $symbols | include "linker_symbols_from_sh" -}}
{{- end -}}

# The VIP of the control plane endpoint, the generic part. The implementations
# are the modules of vip.modules (templates/phases/modules/vip/_<module>.sh.tpl),
# they define vip_<module>_sync (vip_sync calls the one of vip_argname) and
# vip_<module>_reconcile (vip_reconcile calls the one the node was
# bootstrapped with). The arguments of vip_sync replace vip_argname and
# vip_arg.

#!define: vip_arg
# the VIP: the implementation (vip_argname) and its argument, the values
# (vip.init_argname, vip.init_val) or the arguments of vip_sync
vip_argname="{{ $envAll.Values.vip.init_argname | default "" }}"
vip_arg="{{ tpl ($envAll.Values.vip.init_val | default "") $envAll }}"

#!define: VIP_FILE
# the VIP of the bootstrap: the implementation and its argument
VIP_FILE="${ROOTFS}/etc/kubernetes/kubeadm/addons/vip"

#!define: vip_save
#!needs: ensure_dir, vip_arg, VIP_FILE
{{- $addonsDirMode := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_mode" }}
{{- $addonsDirOwner := tuple $envAll "/etc/kubernetes/kubeadm/addons" | include "kubeadm.fs.dir_owner" }}
# the VIP (vip_argname, vip_arg) to VIP_FILE
vip_save() {
  ensure_dir "${VIP_FILE%/*}" "{{ $addonsDirMode }}" "{{ $addonsDirOwner }}"
  printf '%s\n%s\n' "${vip_argname}" "${vip_arg}" > "${VIP_FILE}"
}

#!define: vip_sync
#!needs: vip_save
{{- range $module := $envAll.Values.vip.modules }}
#!needs: vip_{{ $module }}_sync
{{- end }}
# the arguments in VIP_FILE (the reconcile follows the VIP the node was
# bootstrapped with, an empty argument is no VIP), then the VIP of the
# implementation vip_argname; the arguments "<implementation> <argument>"
# replace the values ones
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
  # the nodes bootstrapped before VIP_FILE: the VIP of the values, an empty one
  # isn't saved, the values can set it later
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

#!define: vip_check
#!needs: check_result, vip_configured, vip_reconcile
# reconcile: the first pass of the VIP reconcile (vip_reconcile), the
# reconcile loop repeats it after the anchor is ready and ignores its errors
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
