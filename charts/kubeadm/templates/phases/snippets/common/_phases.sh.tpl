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

{{/* the phases of the node scripts (bootstrap, rebootstrap): a script runs the
     functions phase_<name> of its list of phases in the order of the list,
     the options select them:
       --phases a,b       only these ones
       --skip-phases a,b  all but these ones
       --list-phases      prints the list and exits
     A phase "+<name>" of the list runs only if --phases names it.
     Included by templates/bin/_bootstrap.tpl and _rebootstrap.tpl */ -}}
PHASES_ONLY=""
PHASES_SKIP=""
PHASES_LIST=false

# parses a phase option, phases_shift: the number of the arguments it takes
phases_arg() {
  case "$1" in
    --phases) PHASES_ONLY="${2:?$1 needs a comma separated list of phases}"; phases_shift=2 ;;
    --skip-phases) PHASES_SKIP="${2:?$1 needs a comma separated list of phases}"; phases_shift=2 ;;
    --list-phases) PHASES_LIST=true; phases_shift=1 ;;
    *) return 1 ;;
  esac
}

# the phase is in the comma separated list
phases_in() {
  case ",$2," in
    *",$1,"*) return 0 ;;
  esac
  return 1
}

# checks the phase options against the list of phases, prints the list for
# --list-phases and exits
phases_check() {
  local phase known="" name
  for phase in "$@"; do
    known="${known},${phase#+}"
  done
  for name in ${PHASES_ONLY//,/ } ${PHASES_SKIP//,/ }; do
    if ! phases_in "${name}" "${known#,}"; then
      echo "Unknown phase: ${name} (phases: ${known#,})" >&2
      exit 1
    fi
  done
  if [ "${PHASES_LIST}" = true ]; then
    for phase in "$@"; do
      case "${phase}" in
        +*) echo "${phase#+} (only with --phases)" ;;
        *) echo "${phase}" ;;
      esac
    done
    exit 0
  fi
}

run_phases() {
  local phase name run
  for phase in "$@"; do
    name="${phase#+}"
    if [ -n "${PHASES_ONLY}" ]; then
      phases_in "${name}" "${PHASES_ONLY}" && run=true || run=false
    elif [ "${phase}" != "${name}" ] || phases_in "${name}" "${PHASES_SKIP}"; then
      run=false
    else
      run=true
    fi
    if [ "${run}" = true ]; then
      echo "phase ${name}"
      "phase_${name//-/_}"
    else
      echo "phase ${name}: skipped"
    fi
  done
}
