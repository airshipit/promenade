{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{/* the node checks: called by the bootstrap script (checks.bootstrap) and the
     reconcile script (checks.reconcile), one line per check:
     "check OK|FAIL|SKIP <check> <details>" */}}
{{- define "__checks_lib_functions" -}}
{{- $envAll := . -}}
{{- $checks := $envAll.Values.checks -}}
CHECK_FAILURES=0

check_result() {
  local status="$1"
  shift
  echo "check ${status} $*"
  if [ "${status}" = "FAIL" ]; then
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
  return 0
}

# runs "$@" until it succeeds, checks.attempts times 2 seconds apart
check_attempts() {
  local n=1
  until "$@"; do
    [ "$n" -ge {{ $checks.attempts | int }} ] && return 1
    n=$((n + 1))
    sleep 2
  done
}

# the certificate isn't verified: liveness of the endpoint only
check_livez() {
  curl -ksf --max-time 5 "$1" > /dev/null 2>&1
}

# bootstrap: the node reaches the API through the control plane endpoint
check_api() {
  local url="https://{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}/livez"
  if check_attempts check_livez "${url}"; then
    check_result OK api "${url}"
  else
    check_result FAIL api "${url}: not live"
  fi
  return 0
}

# reconcile: the first pass of the haproxy VIP reconcile (vip_anchor), the
# reconcile loop repeats it after the anchor is ready and ignores its errors
check_vip() {
{{- if $envAll.Values.vip.reconcile }}
  if [ ! -f "${ROOTFS}{{ $envAll.Values.haproxy.host_config_dir }}/haproxy.cfg" ]; then
    check_result SKIP vip "the node has no haproxy VIP"
  elif vip_anchor; then
    check_result OK vip "the haproxy config follows the apiservers"
  else
    check_result FAIL vip "the haproxy config can't follow the apiservers (see above)"
  fi
{{- else }}
  check_result SKIP vip "vip.reconcile is disabled"
{{- end }}
  return 0
}

# runs the given checks, fails if any of them failed: the static pods check
# their own liveness, helm test checks the cluster
run_checks() {
  local check
  CHECK_FAILURES=0
  for check in "$@"; do
    "${check}"
  done
  if [ "${CHECK_FAILURES}" -gt 0 ]; then
    echo "checks: ${CHECK_FAILURES} failed" >&2
    return 1
  fi
  echo "checks passed"
}
{{- end -}}

{{- $_ := set $sharedLibs $sharedLibName (include "__checks_lib_functions" $envAll) -}}
