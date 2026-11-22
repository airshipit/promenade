{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $symbols := get $k8sConfDict "symbols" -}}
{{- $checks := $envAll.Values.checks -}}

{{/* the node checks: called by the check_run phase of the bootstrap and
     rebootstrap scripts and the reconcile script (checks.reconcile), one line
     per check:
     "check OK|FAIL|SKIP <check> <details>"
     the other modules define their <module>_check with check_result
     (vip_check in templates/phases/modules/vip/_.tpl, certs_check in
     templates/phases/modules/certs/_.tpl) */}}
{{- $_ := set $symbols "CHECK_FAILURES" (dict "body" "CHECK_FAILURES=0") -}}

{{- $_ := set $symbols "check_result" (dict "needs" (list "CHECK_FAILURES")
"body" `
check_result() {
  local status="$1"
  shift
  echo "check ${status} $*"
  if [ "${status}" = "FAIL" ]; then
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
  return 0
}
`) -}}

{{- $_ := set $symbols "check_attempts" (dict "body" (printf `
# runs "$@" until it succeeds, checks.attempts times 2 seconds apart
check_attempts() {
  local n=1
  until "$@"; do
    [ "$n" -ge %d ] && return 1
    n=$((n + 1))
    sleep 2
  done
}
` ($checks.attempts | int))) -}}

{{- $_ := set $symbols "check_livez" (dict "body" `
# the certificate isn't verified: liveness of the endpoint only
check_livez() {
  curl -ksf --max-time 5 "$1" > /dev/null 2>&1
}
`) -}}

{{- $_ := set $symbols "check_api" (dict "needs" (list "check_attempts" "check_livez" "check_result")
"body" (printf `
# bootstrap: the node reaches the API through the control plane endpoint
check_api() {
  local url="https://%s/livez"
  if check_attempts check_livez "${url}"; then
    check_result OK api "${url}"
  else
    check_result FAIL api "${url}: not live"
  fi
  return 0
}
` $envAll.Values.kubeconfig.controlPlaneEndpoint)) -}}

{{- $_ := set $symbols "check_run" (dict "needs" (list "CHECK_FAILURES" "check_api")
"body" `
# runs the given checks (check_api without arguments), fails if any of them
# failed: the static pods check their own liveness, helm test checks the cluster
check_run() {
  local check
  [ $# -gt 0 ] || set -- check_api
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
`) -}}
