{{/*
linker: links a script from symbols, like object files into a binary: only the
symbols the script needs, in the order of their dependencies.

Why: the scripts of the chart share the functions of the modules, each script
needs only some of them. A symbol declares what it needs, so does the script,
the linker takes the rest.

Symbols: a dict, name -> symbol.
Symbol: a function or a global variable of the script, a dict:
  needs  the names of the symbols it uses (optional)
  body   the text of the symbol, its comments included
Dependencies are declared, not found in the body: a forgotten one is the
author's problem.

The symbol "" is the environment of the script (the globals, the workarounds):
always linked, first, the other symbols don't need to name it. It has no needs.

Usage:
  {{- $symbols := dict -}}
  {{- $_ := set $symbols "ensure_dir" (dict
        "needs" (list "SKIPPERM")
        "body" `
  # creates the directory
  ensure_dir() { ... }
  `) -}}
  {{ include "linker" (dict "symbols" $symbols "needs" (list "ensure_dir")) }}

Order: the symbols without dependencies first, then the ones needing only
them, and so on; by name inside each step. The output is stable byte by byte:
the hashes of the scripts trigger the rollouts of the anchors.

Fails on an undefined symbol (with the one needing it) and on a cycle.
*/}}

{{/* fails if the symbol isn't a dict with a body and a list of needs */}}
{{- define "_linker_check" -}}
  {{- $name := index . 0 -}}
  {{- $symbol := index . 1 -}}
  {{- if not (kindIs "map" $symbol) -}}
    {{- fail (printf "linker: symbol %s must be a dict" $name) -}}
  {{- end -}}
  {{- if not (kindIs "string" $symbol.body) -}}
    {{- fail (printf "linker: symbol %s needs a body" $name) -}}
  {{- end -}}
  {{- if not (kindIs "slice" ($symbol.needs | default list)) -}}
    {{- fail (printf "linker: the needs of symbol %s must be a list" $name) -}}
  {{- end -}}
  {{- if and (eq $name "") $symbol.needs -}}
    {{- fail "linker: the environment (symbol \"\") has no needs" -}}
  {{- end -}}
{{- end -}}

{{- define "linker" -}}
  {{- $symbols := .symbols -}}

  {{/* the closure of the needs of the script: name -> the symbol needing it */}}
  {{- $linked := dict -}}
  {{- $queue := list -}}
  {{- if hasKey $symbols "" -}}
    {{- $queue = append $queue (list "" "the script") -}}
  {{- end -}}
  {{- range $name := .needs -}}
    {{- $queue = append $queue (list $name "the script") -}}
  {{- end -}}
  {{- range $_ := until (add1 (len $symbols) | int) -}}
    {{- $next := list -}}
    {{- range $item := $queue -}}
      {{- $name := index $item 0 -}}
      {{- if not (hasKey $linked $name) -}}
        {{- if not (hasKey $symbols $name) -}}
          {{- fail (printf "linker: undefined symbol %s (needed by %s)" $name (index $item 1)) -}}
        {{- end -}}
        {{- include "_linker_check" (tuple $name (get $symbols $name)) -}}
        {{- $_ := set $linked $name (index $item 1) -}}
        {{- range $dep := (get $symbols $name).needs | default list -}}
          {{- $next = append $next (list $dep $name) -}}
        {{- end -}}
      {{- end -}}
    {{- end -}}
    {{- $queue = $next -}}
  {{- end -}}

  {{/* each step: the symbols whose dependencies are all linked before, the
       environment first */}}
  {{- $done := dict -}}
  {{- $order := list -}}
  {{- if hasKey $linked "" -}}
    {{- $_ := set $done "" true -}}
    {{- $order = append $order "" -}}
  {{- end -}}
  {{- range $_ := until (len $linked) -}}
    {{- $ready := list -}}
    {{- range $name := keys $linked | sortAlpha -}}
      {{- if not (hasKey $done $name) -}}
        {{- $isReady := true -}}
        {{- range $dep := (get $symbols $name).needs | default list -}}
          {{- if not (hasKey $done $dep) -}}{{- $isReady = false -}}{{- end -}}
        {{- end -}}
        {{- if $isReady -}}{{- $ready = append $ready $name -}}{{- end -}}
      {{- end -}}
    {{- end -}}
    {{- range $name := $ready -}}
      {{- $_ := set $done $name true -}}
      {{- $order = append $order $name -}}
    {{- end -}}
  {{- end -}}
  {{- if lt (len $order) (len $linked) -}}
    {{- $cycle := list -}}
    {{- range $name := keys $linked | sortAlpha -}}
      {{- if not (hasKey $done $name) -}}{{- $cycle = append $cycle $name -}}{{- end -}}
    {{- end -}}
    {{- fail (printf "linker: a cycle among the symbols %s" (join ", " $cycle)) -}}
  {{- end -}}

  {{/* the symbols separated by an empty line */}}
  {{- $texts := list -}}
  {{- range $name := $order -}}
    {{- $texts = append $texts (trim (get $symbols $name).body) -}}
  {{- end -}}
  {{- join "\n\n" $texts -}}
  {{- if $texts }}{{ "\n" }}{{ end -}}
{{- end -}}
