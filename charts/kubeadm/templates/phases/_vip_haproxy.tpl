{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict.fs "all" -}}
{{/* populate static pod anyway so user could use bootstrap command line to enable it */}}
{{/* can be patched with bundle.tpl."templates/phases/snippets/vip/_haproxy.yaml.tpl.patch" */}}
{{- $staticPod := tuple $envAll "templates/phases/snippets/vip/_haproxy.yaml.tpl" $envAll (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.patched_template" -}}
{{- $_ := set $allNodes "_manifests/haproxy.yaml" (dict "content" $staticPod "dest_path" "etc/kubernetes/manifests/haproxy.yaml" "file_mode" 0600 ) -}}


{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{- define "__haproxy_lib_functions" -}}
{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $haproxyHeader := (tuple $envAll "templates/phases/snippets/vip/_haproxy.cfg.header.tpl" | include "kubeadm.bundle.template") -}}

{{- $manifestDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/manifests") | include "kubeadm.bundle.template" -}}
{{- $manifestDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/manifests") | include "kubeadm.bundle.template" -}}
{{- $manifestMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/manifests" "manifests") | include "kubeadm.bundle.template" -}}
{{- $manifestOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/manifests" "manifests") | include "kubeadm.bundle.template" -}}

{{- $addonsDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/addons") | include "kubeadm.bundle.template" -}}
{{- $addonsDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/addons") | include "kubeadm.bundle.template" -}}


sync_vip_config() {
  local kubernetes_dir="/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/manifests" "{{ $manifestDirMode }}" "{{ $manifestDirOwner }}"
  sync_group_dir "${ROOTFS}" "_manifests" "${kubernetes_dir}/manifests" "${NODE_ROLE}" false "{{ $manifestMode }}" "{{ $manifestOwner }}"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm/addons" "{{ $addonsDirMode }}" "{{ $addonsDirOwner }}"
}

# we actually can build default value if we have access to control_plane structures
# here is the example of arg: "*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443,172.29.0.1154:6443"
{{ $vip_init := tpl ($envAll.Values.vip.init | default "") $envAll -}}
{{ $sharedLibName }}_arg="{{ $vip_init }}"
sync_{{ $sharedLibName }}() {
  local arg=${{ $sharedLibName }}_arg

  sync_vip_config

  echo "{{ $sharedLibName }}_arg=$arg"
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

# called by the reconcile loop: the backends of the values (vip.init) plus the
# apiservers of the kubernetes endpointslices. All of them, ready or not:
# haproxy health checks pick the live ones, the list shouldn't flap while the
# control plane restarts. Keeps the current config if the API isn't available.
{{ $sharedLibName }}_anchor() {
    local init_arg="{{ $vip_init }}"
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

    {{ $sharedLibName }}_arg="${bind}|${backends}"
    sync_{{ $sharedLibName }}
}

{{- end -}}

{{- $_ := set $sharedLibs $sharedLibName (include "__haproxy_lib_functions" (tuple $envAll $k8sConfDict $sharedLibName)) -}}
{{- $_ := set $sharedLibs (printf "%s_cmd" $sharedLibName) (printf `
  if [ "$1" == "--vip_haproxy" ]; then
    %s_arg=$2
    addons_shift=2
    return 0
  fi
` $sharedLibName )
-}}

{{/* we also can build vip_haproxy_container content, anchor can synronize info about vip */}}
