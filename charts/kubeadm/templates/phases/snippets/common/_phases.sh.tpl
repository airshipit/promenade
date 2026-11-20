{{/*
Copyright 2025 AT&T Intellectual Property.  All other rights reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/}}

{{/* the phases of the node scripts (bootstrap, rebootstrap): a phase is a
     function of the list of phases of the script, the command line is
       [--run] [-- <phase> [<arguments>]]...
     Without --run the phases of the list run in its order, the segments
     "-- <phase> <arguments>" give the arguments to the phases, a phase
     "+<function>" of the list runs only if a segment names it. With --run the
     segments are the phases to run, in their order. The phase checks its
     arguments and has the defaults.
     A function ending with _rc returns a result: 1 isn't a failure, >1 is.
     Included by templates/bin/_bootstrap.tpl and _rebootstrap.tpl */ -}}
# the arguments of the first segment "-- $1 ..." of "${@:2}" to PHASE_ARGS,
# fails if there is none
phase_args() {
  local name="$1"
  shift
  PHASE_ARGS=()
  while [ $# -gt 0 ] && { [ "$1" != "--" ] || [ "${2:-}" != "${name}" ]; }; do
    shift
  done
  [ $# -gt 0 ] || return 1
  shift 2
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    PHASE_ARGS+=("$1")
    shift
  done
}

# runs the phase $1 with the arguments PHASE_ARGS
phase_run() {
  local rc=0
  echo "phase $1"
  if [[ "$1" == *_rc ]]; then
    "$1" ${PHASE_ARGS[@]+"${PHASE_ARGS[@]}"} || rc=$?
    [ "${rc}" -le 1 ] || exit "${rc}"
  else
    "$1" ${PHASE_ARGS[@]+"${PHASE_ARGS[@]}"}
  fi
}

# runs the phases of PHASES by the command line
run_phases() {
  local phase
  if [ "${1:-}" = "--run" ]; then
    shift
    while [ $# -gt 0 ]; do
      phase_args "$2" "$@"
      phase_run "$2"
      shift $((${#PHASE_ARGS[@]} + 2))
    done
  else
    for phase in "${PHASES[@]}"; do
      if phase_args "${phase#+}" "$@" || [[ "${phase}" != +* ]]; then
        phase_run "${phase#+}"
      else
        echo "phase ${phase#+}: skipped"
      fi
    done
  fi
}
