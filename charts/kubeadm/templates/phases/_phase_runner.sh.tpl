# The runner of the phase-runner script, linked as run_phases. Its command
# line is
#   [--run] [-- <phase> [<arguments>]]...
# Without --run the phases of the profile (PHASES) run in their order, the
# segments "-- <phase> <arguments>" give arguments to them, and a phase
# "+<phase>" of the profile runs only if a segment names it. With --run the
# segments are the phases to run, in their order. A phase checks its
# arguments and has the defaults. A function ending with _rc returns a
# result: 1 isn't a failure, >1 is.

#!define: phase_args
# puts the arguments of the first segment "-- $1 ..." of "${@:2}" to PHASE_ARGS,
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

#!define: phase_run
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

#!define: run_phases
#!needs: phase_args, phase_run
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
