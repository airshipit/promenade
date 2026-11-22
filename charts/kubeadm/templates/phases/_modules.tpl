{{/* The modules of the phases (k8sConfDict.modules).
     To switch a module off, ensure its phases are not used in
     bootstrap.profiles, redefine templates/phases/modules/reconcile/_pass.tpl
     and _tick.tpl in bundle.tpl so they don't use its functions, then redefine
     this file in bundle.tpl with the new list. If a function of the module is
     still needed, the linker fails at render and tells who needs it. The files
     of the module aren't delivered to the nodes either */}}
{{- $k8sConfDict := index . 1 -}}
{{- $_ := set $k8sConfDict "modules" (list
  "templates/phases/modules/backup/_.tpl"
  "templates/phases/modules/binaries/_.tpl"
  "templates/phases/modules/certs/_.tpl"
  "templates/phases/modules/checks/_.tpl"
  "templates/phases/modules/cri/_.tpl"
  "templates/phases/modules/etcd/_.tpl"
  "templates/phases/modules/fs/_.tpl"
  "templates/phases/modules/k8s_up/_.tpl"
  "templates/phases/modules/kube-cgroup/_.tpl"
  "templates/phases/modules/kubeadm/_.tpl"
  "templates/phases/modules/kubeconfig/_.tpl"
  "templates/phases/modules/kubelet/_.tpl"
  "templates/phases/modules/rebootstrap/_.tpl"
  "templates/phases/modules/reconcile/_.tpl"
  "templates/phases/modules/vip/_.tpl"
) -}}
