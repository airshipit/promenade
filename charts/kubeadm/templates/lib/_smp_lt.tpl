{{/*
smp-light: a subset of the Kubernetes strategic merge patch in Go templates.

Why: mergeOverwrite replaces lists, so a patch adding one env variable to a
container has to repeat the whole list of the containers. Here the lists of
the known types are merged by their keys, as kubectl does.

Usage:
  {{- $schema := dict -}}
  {{- $_ := include "strategic_merge_patch_schema" $schema -}}
  {{- $out := dict -}}
  {{- $_ := include "strategic_merge_patch" (tuple $schema $gvk $base $patch $out) -}}
- schema: the merge rules, strategic_merge_patch_schema populates the ones of
  the kinds the chart generates, the caller can extend or replace them
- gvk: the type of the base in the schema, "<apiVersion>/<kind>", e.g.
  "apps/v1/DaemonSet". A type which isn't in the schema is merged as maps,
  its lists are replaced
- base, patch: dicts, they aren't modified
- out: an empty dict the result is written to (without a round trip through
  json). The result shares the unpatched values with the base

Schema: gvk -> path of the field in the type (dot separated) -> rule:
  "spec.template.spec": {"$ref": "v1/PodSpec"}             the field is of another type
  "containers": {"strategy": "merge", "key": "name",
                 "$ref": "v1/Container"}                     a list merged by the key,
                                                             its elements are of the type
Lists without a rule are replaced.

Patch semantics:
- maps are merged recursively, a field set to null is removed
- "$patch: replace" in a map replaces it, "$patch: delete" removes it
- lists merged by a key keep the order of the base, new elements are appended
  in the order of the patch, an element with "$patch: delete" is removed,
  an element {"$patch": "replace"} replaces the whole list
- other directives ($retainKeys, $setElementOrder, $deleteFromPrimitiveList)
  aren't supported and fail
*/}}

{{/* populates the dict with the schema of the kinds the chart generates */}}
{{- define "strategic_merge_patch_schema" -}}
  {{- $schema := . -}}

  {{- $_ := set $schema "v1/Container" (dict
    "ports" (dict "strategy" "merge" "key" "containerPort")
    "env" (dict "strategy" "merge" "key" "name")
    "volumeMounts" (dict "strategy" "merge" "key" "mountPath")
    "volumeDevices" (dict "strategy" "merge" "key" "devicePath")
    "resizePolicy" (dict "strategy" "merge" "key" "resourceName")
  ) -}}

  {{- $_ := set $schema "v1/PodSpec" (dict
    "containers" (dict "strategy" "merge" "key" "name" "$ref" "v1/Container")
    "initContainers" (dict "strategy" "merge" "key" "name" "$ref" "v1/Container")
    "ephemeralContainers" (dict "strategy" "merge" "key" "name" "$ref" "v1/Container")
    "volumes" (dict "strategy" "merge" "key" "name")
    "imagePullSecrets" (dict "strategy" "merge" "key" "name")
    "hostAliases" (dict "strategy" "merge" "key" "ip")
    "resourceClaims" (dict "strategy" "merge" "key" "name")
    "schedulingGates" (dict "strategy" "merge" "key" "name")
  ) -}}

  {{/* the kinds with pods, every kind has its own dicts: the caller may
       extend one of them */}}
  {{- $_ := set $schema "v1/Pod" (dict "spec" (dict "$ref" "v1/PodSpec")) -}}
  {{- $_ := set $schema "v1/PodTemplate" (dict "template.spec" (dict "$ref" "v1/PodSpec")) -}}
  {{- range $kind := list "apps/v1/Deployment" "apps/v1/DaemonSet" "apps/v1/ReplicaSet" "apps/v1/StatefulSet" "batch/v1/Job" -}}
    {{- $_ := set $schema $kind (dict "spec.template.spec" (dict "$ref" "v1/PodSpec")) -}}
  {{- end -}}
  {{- $_ := set $schema "batch/v1/CronJob" (dict "spec.jobTemplate.spec.template.spec" (dict "$ref" "v1/PodSpec")) -}}

  {{- $_ := set $schema "v1/Service" (dict
    "spec.ports" (dict "strategy" "merge" "key" "port")
  ) -}}
{{- end -}}

{{/* the "$patch" directive of the map, "" if there is none */}}
{{- define "_smp_directive" -}}
  {{- if kindIs "map" . -}}{{- index . "$patch" | default "" -}}{{- end -}}
{{- end -}}

{{/* merges the maps (.base, .patch) of the type (.gvk, .path) into .out */}}
{{- define "_smp_map" -}}
  {{- $ctx := . -}}
  {{- $base := .base -}}
  {{- $patch := .patch -}}
  {{- $rules := index .schema .gvk | default dict -}}

  {{- $directive := include "_smp_directive" $patch -}}
  {{- if eq $directive "replace" -}}
    {{- $base = dict -}}
  {{- else if not (or (eq $directive "") (eq $directive "merge")) -}}
    {{- fail (printf "strategic_merge_patch: unsupported $patch: %s in %s %s" $directive .gvk .path) -}}
  {{- end -}}

  {{- range $k, $v := $base -}}
    {{- if not (hasKey $patch $k) -}}
      {{- $_ := set $ctx.out $k $v -}}
    {{- end -}}
  {{- end -}}

  {{- range $k, $p := $patch -}}
    {{- if hasPrefix "$" $k -}}
      {{- if ne $k "$patch" -}}
        {{- fail (printf "strategic_merge_patch: unsupported directive %s in %s %s" $k $ctx.gvk $ctx.path) -}}
      {{- end -}}
    {{/* null removes the field */}}
    {{- else if not (kindIs "invalid" $p) -}}
      {{- $field := $k -}}
      {{- if $ctx.path -}}{{- $field = printf "%s.%s" $ctx.path $k -}}{{- end -}}
      {{- $_ := include "_smp_value" (dict
        "schema" $ctx.schema "gvk" $ctx.gvk "path" $field
        "rule" (index $rules $field | default dict)
        "base" (index $base $k) "patch" $p "out" $ctx.out "key" $k) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{/* sets .out[.key] to the value .base patched with .patch (the field .path
     of .gvk, .rule is its schema rule) */}}
{{- define "_smp_value" -}}
  {{- if kindIs "map" .patch -}}
    {{- if ne (include "_smp_directive" .patch) "delete" -}}
      {{- $gvk := .gvk -}}
      {{- $path := .path -}}
      {{- if hasKey .rule "$ref" -}}
        {{- $gvk = index .rule "$ref" -}}
        {{- $path = "" -}}
      {{- end -}}
      {{- $base := .base -}}
      {{- if not (kindIs "map" $base) -}}{{- $base = dict -}}{{- end -}}
      {{- $m := dict -}}
      {{- $_ := include "_smp_map" (dict "schema" .schema "gvk" $gvk "path" $path "base" $base "patch" .patch "out" $m) -}}
      {{- $_ := set .out .key $m -}}
    {{- end -}}
  {{- else if kindIs "slice" .patch -}}
    {{- include "_smp_list" . -}}
  {{- else -}}
    {{- $_ := set .out .key .patch -}}
  {{- end -}}
{{- end -}}

{{/* the element of the list without directives and null fields */}}
{{- define "_smp_clean" -}}
  {{- if kindIs "map" .patch -}}
    {{- $m := dict -}}
    {{- $_ := include "_smp_map" (dict "schema" .schema "gvk" .gvk "path" .path "base" (dict) "patch" .patch "out" $m) -}}
    {{- $_ := set .out "v" $m -}}
  {{- else -}}
    {{- $_ := set .out "v" .patch -}}
  {{- end -}}
{{- end -}}

{{/* sets .out[.key] to the list .base patched with .patch */}}
{{- define "_smp_list" -}}
  {{- $ctx := . -}}
  {{- $base := .base -}}
  {{- if not (kindIs "slice" $base) -}}{{- $base = list -}}{{- end -}}
  {{- $strategy := index .rule "strategy" | default "replace" -}}
  {{- $mergeKey := index .rule "key" | default "" -}}
  {{- $elem := dict "schema" .schema "gvk" .gvk "path" .path -}}
  {{- if hasKey .rule "$ref" -}}
    {{- $_ := set $elem "gvk" (index .rule "$ref") -}}
    {{- $_ := set $elem "path" "" -}}
  {{- end -}}

  {{/* {"$patch": "replace"} element replaces the list */}}
  {{- $items := list -}}
  {{- range $p := .patch -}}
    {{- if and (kindIs "map" $p) (eq (len $p) 1) (eq (include "_smp_directive" $p) "replace") -}}
      {{- $strategy = "replace" -}}
    {{- else -}}
      {{- $items = append $items $p -}}
    {{- end -}}
  {{- end -}}

  {{- $result := list -}}
  {{- $holder := dict -}}
  {{- if or (eq $strategy "replace") (not $mergeKey) -}}
    {{- range $p := $items -}}
      {{- $_ := include "_smp_clean" (merge (dict "patch" $p "out" $holder) $elem) -}}
      {{- $result = append $result $holder.v -}}
    {{- end -}}
  {{- else -}}
    {{- $byKey := dict -}}
    {{- range $p := $items -}}
      {{- if and (kindIs "map" $p) (hasKey $p $mergeKey) -}}
        {{- $_ := set $byKey (printf "%v" (index $p $mergeKey)) $p -}}
      {{- end -}}
    {{- end -}}

    {{/* the base in its order, patched */}}
    {{- $seen := dict -}}
    {{- range $b := $base -}}
      {{- $key := "" -}}
      {{- if and (kindIs "map" $b) (hasKey $b $mergeKey) -}}
        {{- $key = printf "%v" (index $b $mergeKey) -}}
      {{- end -}}
      {{- if and $key (hasKey $byKey $key) -}}
        {{- $_ := set $seen $key true -}}
        {{- $p := index $byKey $key -}}
        {{- if ne (include "_smp_directive" $p) "delete" -}}
          {{- $m := dict -}}
          {{- $_ := include "_smp_map" (merge (dict "base" $b "patch" $p "out" $m) $elem) -}}
          {{- $result = append $result $m -}}
        {{- end -}}
      {{- else -}}
        {{- $result = append $result $b -}}
      {{- end -}}
    {{- end -}}

    {{/* the new elements in the order of the patch */}}
    {{- range $p := $items -}}
      {{- $key := "" -}}
      {{- if and (kindIs "map" $p) (hasKey $p $mergeKey) -}}
        {{- $key = printf "%v" (index $p $mergeKey) -}}
      {{- end -}}
      {{- if not (and $key (or (hasKey $seen $key) (eq (include "_smp_directive" $p) "delete"))) -}}
        {{- $_ := include "_smp_clean" (merge (dict "patch" $p "out" $holder) $elem) -}}
        {{- $result = append $result $holder.v -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
  {{- $_ := set .out .key $result -}}
{{- end -}}

{{- define "strategic_merge_patch" -}}
  {{- $schema := index . 0 -}}
  {{- $gvk := index . 1 -}}
  {{- $base := index . 2 -}}
  {{- $patch := index . 3 | default dict -}}
  {{- $out := index . 4 -}}
  {{- if not (kindIs "map" $schema) -}}{{- fail "strategic_merge_patch: the schema must be a dict" -}}{{- end -}}
  {{- if not (kindIs "string" $gvk) -}}{{- fail "strategic_merge_patch: the gvk must be a string" -}}{{- end -}}
  {{- if not (kindIs "map" $base) -}}{{- fail "strategic_merge_patch: the base must be a dict" -}}{{- end -}}
  {{- if not (kindIs "map" $patch) -}}{{- fail "strategic_merge_patch: the patch must be a dict" -}}{{- end -}}
  {{- if not (kindIs "map" $out) -}}{{- fail "strategic_merge_patch: the last argument must be a dict for the result" -}}{{- end -}}
  {{- if $out -}}{{- fail "strategic_merge_patch: the dict for the result must be empty" -}}{{- end -}}

  {{- $_ := include "_smp_map" (dict "schema" $schema "gvk" $gvk "path" "" "base" $base "patch" $patch "out" $out) -}}
{{- end -}}
