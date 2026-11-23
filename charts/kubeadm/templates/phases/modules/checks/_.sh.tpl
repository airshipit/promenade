{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# The node checks: called by the check_run phase of the bootstrap and
# rebootstrap scripts and the reconcile script (anchor.reconcile.checks), one
# line per check:
#   check OK|FAIL|SKIP <check> <details>
# The other modules define their <module>_check with check_result (vip_check
# of the vip module, certs_check of the certs module).

#!define: CHECK_FAILURES
CHECK_FAILURES=0

#!define: check_result
#!needs: CHECK_FAILURES
check_result() {
  local status="$1"
  shift
  echo "check ${status} $*"
  if [ "${status}" = "FAIL" ]; then
    CHECK_FAILURES=$((CHECK_FAILURES + 1))
  fi
  return 0
}

#!define: check_attempts
# runs "$@" until it succeeds, checks.attempts times 2 seconds apart
check_attempts() {
  local n=1
  until "$@"; do
    [ "$n" -ge {{ $envAll.Values.checks.attempts | int }} ] && return 1
    n=$((n + 1))
    sleep 2
  done
}

#!define: check_livez
# the certificate isn't verified: liveness of the endpoint only
check_livez() {
  curl -ksf --max-time 5 "$1" > /dev/null 2>&1
}

#!define: check_api
#!needs: check_attempts, check_livez, check_result
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

#!define: check_run
#!needs: CHECK_FAILURES, check_api
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
