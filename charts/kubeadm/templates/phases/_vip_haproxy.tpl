{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $allNodes := get $k8sConfDict "allNodes" -}}
{{/* populate static pod anyway so user could use bootstrap command line to enable it */}}
{{ $patch := dict -}}
{{- if hasKey $envAll.Values.bundle.tpl "templates/phases/snippets/vip/_haproxy.yaml.tpl.patch" -}}
  {{- $patch = tuple $envAll "templates/phases/snippets/vip/_haproxy.yaml.tpl.patch" (tuple $envAll $k8sConfDict) | include "kubeadm.bundle.template" | fromYaml -}}
{{- end -}}
{{- $staticPod := $patch | mergeOverwrite (tuple $envAll "templates/phases/snippets/vip/_haproxy.yaml.tpl" | include "kubeadm.bundle.template" | fromYaml) | toYaml -}}
{{- $_ := set $allNodes "manifests_haproxy.yaml" (dict "content" $staticPod "dest_path" "etc/kubernetes/manifests/haproxy.yaml" "file_mode" 0600 ) -}}


{{- $sharedLibs := get $k8sConfDict "sharedLibs" -}}

{{- define "__haproxy_lib_functions" -}}
{{- $envAll := index . 0 -}}
{{- $k8sConfDict := index . 1 -}}
{{- $sharedLibName := index . 2 -}}

{{- $haproxyHeader := (tuple $envAll "templates/phases/snippets/vip/_haproxy.cfg.header.tpl" | include "kubeadm.bundle.template") -}}

{{- $manifestDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/manifests") | include "kubeadm.bundle.template" -}}
{{- $manifestDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/manifests") | include "kubeadm.bundle.template" -}}
{{- $manifestMode := tuple $envAll "templates/phases/snippets/common/_file_mode.tpl" (tuple $envAll "/etc/kubernetes/manifests" "manifests_") | include "kubeadm.bundle.template" -}}
{{- $manifestOwner := tuple $envAll "templates/phases/snippets/common/_file_owner.tpl" (tuple $envAll "/etc/kubernetes/manifests" "manifests_") | include "kubeadm.bundle.template" -}}

{{- $addonsDirMode := tuple $envAll "templates/phases/snippets/common/_dir_mode.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/addons") | include "kubeadm.bundle.template" -}}
{{- $addonsDirOwner := tuple $envAll "templates/phases/snippets/common/_dir_owner.tpl" (tuple $envAll "/etc/kubernetes/kubeadm/addons") | include "kubeadm.bundle.template" -}}


sync_vip_config() {
  local kubernetes_dir="${HOST_DIR}/etc/kubernetes"

  ensure_dir "${ROOTFS}${kubernetes_dir}/manifests" "{{ $manifestDirMode }}" "{{ $manifestDirOwner }}"
  sync_prefix_based_dir "${ROOTFS}" "${kubernetes_dir}/manifests" "manifests_" "${NODE_ROLE}" false "{{ $manifestMode }}" "{{ $manifestOwner }}"

  ensure_dir "${ROOTFS}${kubernetes_dir}/kubeadm/addons" "{{ $addonsDirMode }}" "{{ $addonsDirOwner }}"
}

# we actually can build default value if we have access to control_plane structures
# here is the example of arg: "*:6553|172.29.0.139:6443,172.29.0.144:6443,172.29.0.149:6443,172.29.0.1154:6443"
{{ $vip_init := "" -}}
{{- if $envAll.Values.vip -}}
{{- $vip_init = tpl ($envAll.Values.vip.init | default "") $envAll }}
{{- end -}}
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
    NEXT_HAPROXY_CONF="${ROOTFS}${HOST_DIR}{{ $envAll.Values.haproxy.host_config_dir }}/haproxy.cfg"
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
  fi
  echo "vip(haproxy) is synced"
}

# detect config from service endpointslices
{{ $sharedLibName }}_anchor() {
    local hostroot="$1"
    local node_role="$2"

    local SERVICE_IPS
    SERVICE_IPS=$(set -o pipefail; kubectl \
        --server "$KUBE_URL" \
        --certificate-authority "$KUBE_CA" \
        --token "$(cat "$KUBE_TOKEN")" \
        --namespace default \
            get endpointslices kubernetes \
                -o jsonpath='{range .ports[*]}{$port:=.port}{range $.endpoints[?(@.conditions.ready==true)]}{range .addresses}{.}:{$port}{","}{end}{end}{end}' | sed 's/,$//')

    if [ $? -ne 0 ]; then
      echo "Unable to retrieve service IPs for kubernetes, will retry configuration render."
      return 1
    fi

    IFS=':' read -r BIND_IP BIND_PORT <<< "{{ $envAll.Values.kubeconfig.controlPlaneEndpoint }}"

    if [ -n "${SERVICE_IPS}" ]; then
      {{ $sharedLibName }}_arg="*:${BIND_PORT}|${SERVICE_IPS}"
      sync_{{ $sharedLibName }}
    fi
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
