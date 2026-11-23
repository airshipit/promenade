{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}

{{- $allNodes := get (get $k8sConfDict "fs") "all" -}}
{{/* the haproxy implementation of the VIP (vip.modules, templates/phases/modules/vip/_.sh.tpl) */}}
{{/* populate static pod anyway so user could use bootstrap command line to enable it */}}
{{/* can be patched with bundle.tpl."templates/phases/modules/vip/_pod-haproxy.yaml.patch" */}}
{{- $staticPod := tuple $envAll "templates/phases/modules/vip/_pod-haproxy.yaml" $envAll (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" -}}
{{- $_ := set $allNodes "_manifests/haproxy.yaml" (dict "content" $staticPod "dest_path" "etc/kubernetes/manifests/haproxy.yaml" "file_mode" 0600 ) -}}

{{/* the argument (vip_sync haproxy <arg>, vip.init_val):
     "<bind>|<apiserver>,<apiserver>,...", e.g.
     "*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443" */}}

#!define: vip_config_sync
#!needs: ensure_dir, group_dir_sync
{{- $manifestDirMode := tuple $envAll "/etc/kubernetes/manifests" | include "kubeadm.fs.dir_mode" }}
{{- $manifestDirOwner := tuple $envAll "/etc/kubernetes/manifests" | include "kubeadm.fs.dir_owner" }}
{{- $manifestMode := tuple $envAll "vip" "manifests" | include "kubeadm.fs.file_mode" }}
{{- $manifestOwner := tuple $envAll "vip" "manifests" | include "kubeadm.fs.file_owner" }}
vip_config_sync() {
  local kubernetes_dir="/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/manifests" "{{ $manifestDirMode }}" "{{ $manifestDirOwner }}"
  group_dir_sync "${ROOTFS}" "_manifests" "${kubernetes_dir}/manifests" "${NODE_ROLE}" false "{{ $manifestMode }}" "{{ $manifestOwner }}"
}

#!define: vip_haproxy_sync
#!needs: vip_config_sync, vip_arg
{{- $haproxyHeader := (tuple $envAll "templates/phases/modules/vip/_haproxy.cfg.header.tpl" | include "kubeadm.bundle.template") }}
vip_haproxy_sync() {
  local arg=$vip_arg

  vip_config_sync

  echo "vip_arg=$arg"
  if [[ -n "$arg" ]]; then
    # VIP and the rest
    IFS='|' read -r VIP RAW_IPS <<< "$arg"
    IFS=':' read -r BIND_IP BIND_PORT <<< "$VIP"

    # split
    IFS=',' read -r -a SERVICE_ENDPOINTS <<< "$RAW_IPS"

    IDENTIFIER="default-kubernetes"
    # the haproxy static pod polls haproxy.cfg: it's built aside and moved in
    # place, a partially written file (e.g. the header only) is a valid config
    # without frontends
    HAPROXY_CONF="${ROOTFS}{{ $envAll.Values.haproxy.host_config_dir }}/haproxy.cfg"
    NEXT_HAPROXY_CONF="${HAPROXY_CONF}.next"
    echo "Adding $IDENTIFIER to haproxy config"
    cat << EOF_TEMPLATE_DATA > "$NEXT_HAPROXY_CONF"
{{ $haproxyHeader }}
EOF_TEMPLATE_DATA
    echo "frontend ${IDENTIFIER}-fe" >> "$NEXT_HAPROXY_CONF"

    {{- range $envAll.Values.haproxy.conf_parts.frontend }}
    echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
    {{- end }}
    echo "Adding frontend $BIND_IP:$BIND_PORT"
    echo "  bind $BIND_IP:$BIND_PORT" >> "$NEXT_HAPROXY_CONF"
    echo "  default_backend ${IDENTIFIER}-be" >> "$NEXT_HAPROXY_CONF"

    # Add backend config
    echo >> "$NEXT_HAPROXY_CONF"
    echo "backend ${IDENTIFIER}-be" >> "$NEXT_HAPROXY_CONF"
    {{- range $envAll.Values.haproxy.conf_parts.backend }}
    echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
    {{- end }}

    for ENDPOINT in "${SERVICE_ENDPOINTS[@]}"; do
        IFS=':' read -r IP PORT <<< "$ENDPOINT"
        echo "Adding backend $IP:$PORT"
        echo "  server s$IP $IP:$PORT check port $PORT" >> "$NEXT_HAPROXY_CONF"
    done

    if ! grep -q '^frontend ' "$NEXT_HAPROXY_CONF" || ! grep -q '^  server ' "$NEXT_HAPROXY_CONF"; then
      echo "haproxy config has no frontend or backend servers, keeping the current one"
      rm -f "$NEXT_HAPROXY_CONF"
      return 1
    fi
    if [ -f "$HAPROXY_CONF" ] && cmp -s "$NEXT_HAPROXY_CONF" "$HAPROXY_CONF"; then
      rm -f "$NEXT_HAPROXY_CONF"
    else
      mv "$NEXT_HAPROXY_CONF" "$HAPROXY_CONF"
    fi
  fi
  echo "vip(haproxy) is synced"
}

#!define: vip_haproxy_reconcile
#!needs: vip_arg, vip_haproxy_sync
# called by vip_reconcile: the bind and the backends of the bootstrap (vip_arg
# of VIP_FILE) plus the apiservers of the kubernetes endpointslices. All of
# them, ready or not: haproxy health checks pick the live ones, the list
# shouldn't flap while the control plane restarts. Keeps the current config if
# the API isn't available.
vip_haproxy_reconcile() {
  local init_arg="${vip_arg}"
  local bind init_backends service_endpoints backends

  IFS='|' read -r bind init_backends <<< "$init_arg"
  if [[ -z "$bind" ]]; then
    bind="*:{{ splitList ":" $envAll.Values.kubeconfig.controlPlaneEndpoint | last }}"
  fi

  # "<port> <address> <address> ..." per endpointslice
  if ! service_endpoints=$(kubectl --namespace default get endpointslices \
      -l kubernetes.io/service-name=kubernetes \
      -o jsonpath='{range .items[*]}{.ports[0].port}{" "}{.endpoints[*].addresses[*]}{"\n"}{end}'); then
    echo "Unable to retrieve the kubernetes endpointslices, keeping the current haproxy config"
    return 1
  fi
  service_endpoints=$(awk '{ for (i = 2; i <= NF; i++) print $i ":" $1 }' <<< "$service_endpoints")

  backends=$(printf '%s\n%s\n' "${init_backends//,/$'\n'}" "$service_endpoints" | sed '/^$/d' | sort -u | paste -sd, -)
  if [[ -z "$backends" ]]; then
    echo "No apiservers found, keeping the current haproxy config"
    return 1
  fi

  vip_arg="${bind}|${backends}"
  vip_haproxy_sync
}
