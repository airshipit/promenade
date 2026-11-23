{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

# The rebootstrap profile (bootstrap.profiles.rebootstrap): the lock of the
# reconcile (reconcile_guard) and the restart of the clients of the old CA
# (restart_clients).

#!define: RECONCILE_DIR
RECONCILE_DIR={{ $envAll.Values.anchor.reconcile.host_dir | quote }}

#!define: reconcile_in_flight
#!needs: RECONCILE_DIR
# the reconcile passes going on on the node: the reconcile processes neither
# done nor waiting for the rebootstrap (the files of the anchor are in the mount
# namespace of its pod)
reconcile_in_flight() {
  local pid
  for pid in $(pgrep -f "^/bin/bash ${RECONCILE_DIR}/bin/reconcile" || true); do
    [ -e "/proc/${pid}/root${RECONCILE_DIR}/done" ] ||
      [ -e "/proc/${pid}/root${RECONCILE_DIR}/rebootstrap-wait" ] ||
      echo "${pid}"
  done
}

#!define: delete_pods
# the pods of the selector, the API of the restarted control plane may be
# unavailable for a while
delete_pods() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf")
  local delay
  for delay in 0 1 2 4 8; do
    sleep "${delay}"
    "${kubectl[@]}" delete pods --all-namespaces -l "$1" --grace-period=0 --force && return 0
  done
  return 1
}

#!define: wait_root_ca
# the new CA in kube-root-ca.crt of all the namespaces (the controller-manager
# publishes it): the pods started before it get the old one and keep it
wait_root_ca() {
  local kubectl=(kubectl --kubeconfig "${ROOTFS}/etc/kubernetes/admin.conf")
  local ca namespaces ns stale="" i
  ca=$(cat "${ROOTFS}/etc/kubernetes/pki/ca.crt") || return 1
  for i in $(seq 60); do
    if namespaces=$("${kubectl[@]}" get namespaces -o name) && [ -n "${namespaces}" ]; then
      stale=""
      for ns in ${namespaces}; do
        ns="${ns#namespace/}"
        [ "$("${kubectl[@]}" -n "${ns}" get configmap kube-root-ca.crt -o jsonpath='{.data.ca\.crt}')" = "${ca}" ] ||
          stale="${stale} ${ns}"
      done
      [ -n "${stale}" ] || return 0
    fi
    sleep 2
  done
  echo "kube-root-ca.crt without the new CA:${stale:- (no namespaces)}" >&2
  return 1
}

#!define: reconcile_guard
#!needs: reconcile_in_flight
# the anchors of the node mustn't put the certificates of the values in the
# cluster back: they wait while the backups exist (the lock). The passes going
# on finish first
reconcile_guard() {
  local script pids deadline
  # kubelet keeps the ConfigMap volumes up to date: the script a restarted
  # anchor runs
  for script in "${ROOTFS}"/var/lib/kubelet/pods/*/volumes/kubernetes.io~configmap/bin/reconcile; do
    [ -f "${script}" ] || continue
    if ! grep -q wait_rebootstrap "${script}"; then
      echo "the anchor of ${script} doesn't wait for the rebootstrap: deploy the chart with it first" >&2
      return 1
    fi
  done
  mkdir -p -m 0700 "${ROOTFS}{{ $envAll.Values.backup.dir }}"
  deadline=$((SECONDS + {{ $envAll.Values.bootstrap.rebootstrap_reconcile_timeout | int }}))
  while pids=$(reconcile_in_flight) && [ -n "${pids}" ]; do
    if [ "${SECONDS}" -ge "${deadline}" ]; then
      echo "the reconcile passes $(echo ${pids}) didn't finish in {{ $envAll.Values.bootstrap.rebootstrap_reconcile_timeout | int }}s, the lock {{ $envAll.Values.backup.dir }} is kept" >&2
      return 1
    fi
    echo "waiting for the reconcile passes $(echo ${pids})"
    sleep 10
  done
  echo "the reconcile is locked: {{ $envAll.Values.backup.dir }}"
}

#!define: restart_clients
#!needs: wait_root_ca, delete_pods
# the abrupt rotation: the pods keep the CA (kube-root-ca.crt) and the service
# account tokens they started with, they don't work anyway, their controllers
# start them again once the new CA is published
restart_clients() {
  wait_root_ca || return 1
{{- range $selector := $envAll.Values.bootstrap.rebootstrap_restart_selectors }}
  delete_pods {{ $selector | quote }}
{{- end }}
  return 0
}
