{{- $envAll := index . 0 -}}
{{- $mainDict := index . 1 -}}

# Other modules define their checks with check_result, check_run runs them by
# name.

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
# runs "$@" until it succeeds, up to checks.attempts times 2 seconds apart
check_attempts() {
  local n=1
  until "$@"; do
    [ "$n" -ge {{ $envAll.Values.checks.attempts | int }} ] && return 1
    n=$((n + 1))
    sleep 2
  done
}

#!define: check_api
#!needs: check_attempts, check_result

# checks only the liveness of the endpoint, its certificate isn't verified
_check_livez() {
  curl -ksf --max-time 5 "$1" > /dev/null 2>&1
}

# checks that the node reaches the API through the control plane endpoint
check_api() {
  local url="https://{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}/livez"
  if check_attempts _check_livez "${url}"; then
    check_result OK api "${url}"
  else
    check_result FAIL api "${url}: not live"
  fi
  return 0
}

#!define: check_run
#!needs: CHECK_FAILURES, check_api
# runs the given checks (default: check_api) and fails if any of them failed
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
