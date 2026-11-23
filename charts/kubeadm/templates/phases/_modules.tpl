{{/* The files of the modules of the phases. Each one is rendered with
     (tuple $envAll $k8sConfDict) and given to the linker: its #!define: and
     #!needs: directives register its symbols (linker_symbols_from_sh,
     templates/lib/_linker.tpl). A file given as (list "<path>" false) is only
     rendered, linker_symbols_from_sh isn't called for it, e.g. a module of
     templates which sets its symbols itself. The text before the first
     #!define: of a file is its header: comments only
     (kubeadm.phases.header_check).
     To switch a module off, ensure its phases are not used in
     phase_runner.profiles, redefine templates/phases/modules/reconcile/_.sh.tpl
     in bundle.tpl so it doesn't use its functions, then redefine this file in
     bundle.tpl with the new list. If a function of the module is still
     needed, the linker fails at render and tells who needs it. The files of
     the module aren't delivered to the nodes either */}}
{{/* fails if the header of the file (tuple <path> <header>) has anything but
     comments: the code there would be lost, a #!needs: there has no symbol */}}
{{- define "kubeadm.phases.header_check" -}}
  {{- $path := index . 0 -}}
  {{- range $line := splitList "\n" (index . 1) -}}
    {{- if hasPrefix "#!needs:" (trim $line) -}}
      {{- fail (printf "%s: #!needs: before the first #!define: %s" $path $line) -}}
    {{- end -}}
    {{- if and (trim $line) (not (hasPrefix "#" (trim $line))) -}}
      {{- fail (printf "%s: only comments are allowed before the first #!define:, got: %s" $path $line) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}

{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $modules := list
  "templates/phases/modules/backup/_.sh.tpl"
  "templates/phases/modules/binaries/_.sh.tpl"
  "templates/phases/modules/certs/_.sh.tpl"
  "templates/phases/modules/checks/_.sh.tpl"
  "templates/phases/modules/cri/_.sh.tpl"
  "templates/phases/modules/etcd/_.sh.tpl"
  "templates/phases/modules/fs/_.sh.tpl"
  "templates/phases/modules/kube-cgroup/_.sh.tpl"
  "templates/phases/modules/kubeadm/_.sh.tpl"
  "templates/phases/modules/kubeconfig/_.sh.tpl"
  "templates/phases/modules/kubelet/_.sh.tpl"
  "templates/phases/modules/os/_.sh.tpl"
  "templates/phases/modules/reconcile/_.sh.tpl"
  "templates/phases/modules/reconcile/_lib.sh.tpl"
  "templates/phases/modules/vip/_.sh.tpl"
-}}
{{- range $module := $modules -}}
  {{- $path := $module -}}
  {{- $callSymbolsFromSh := true -}}
  {{- if kindIs "slice" $module -}}
    {{- $path = index $module 0 -}}
    {{- $callSymbolsFromSh = index $module 1 -}}
  {{- end -}}
  {{- $text := tuple $envAll $path (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" -}}
  {{- if $callSymbolsFromSh -}}
    {{- $_ := tuple (get $k8sConfDict "symbols") $text | include "linker_symbols_from_sh" | tuple $path | include "kubeadm.phases.header_check" -}}
  {{- end -}}
{{- end -}}
