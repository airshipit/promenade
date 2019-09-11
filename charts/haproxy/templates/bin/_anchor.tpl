#!/bin/sh
{{/*
Copyright 2018 AT&T Intellectual Property.  All other rights reserved.

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

{{- $envAll := . }}

set -x

compare_copy_files() {
    {{- range .Values.conf.anchor.files_to_copy }}
    if [ ! -e /host{{ .dest }} ] || ! cmp -s {{ .source }} /host{{ .dest }}; then
        mkdir -p $(dirname /host{{ .dest }})
        cp {{ .source }} /host{{ .dest }}
        chmod go-rwx /host{{ .dest }}
    fi
    {{- end }}
}

{{ $fe_count := 0 }}

install_config() {
    SUCCESS=1
    # Inject global and default config
    mkdir -p $(dirname "$HAPROXY_CONF")
    cat "$HAPROXY_HEADER" > "$NEXT_HAPROXY_CONF"

    {{- range $namespace, $services := $envAll.Values.conf.anchor.services }}
    {{- range $service, $svc_data := $services }}
    {{- if $svc_data }}
    {{- $fe_count = add $fe_count 1 }}

    echo Constructing config for namespace=\"{{ $namespace }}\" service=\"{{ $service }}\"

    # NOTE(mark-burnett): Don't accidentally log service account token.
    set +x
    SERVICE_IPS=$(kubectl \
        --server "$KUBE_URL" \
        --certificate-authority "$KUBE_CA" \
        --token $(cat "$KUBE_TOKEN") \
        --namespace {{ $namespace }} \
            get endpoints {{ $service }} \
                -o 'jsonpath={.subsets[0].addresses[*].ip}')

    if [ $? -ne 0]; then
      echo "Unable to retrieve service IPs for {{ $service }}, will retry configuration render."
      return 1
    fi

    DEST_PORT=$(kubectl \
        --server "$KUBE_URL" \
        --certificate-authority "$KUBE_CA" \
        --token $(cat "$KUBE_TOKEN") \
        --namespace {{ $namespace }} \
            get endpoints {{ $service }} \
                -o 'jsonpath={.subsets[0].ports[0].port}')

    if [ $? -ne 0]; then
      echo "Unable to retrieve service port for {{ $service }}, will retry configuration render."
      return 1
    fi

    set -x

    if [ "x$SERVICE_IPS" != "x" ]; then
        if [ "x$DEST_PORT" != "x" ]; then
            IDENTIFIER=$(echo "{{ $namespace }}-{{ $service }}")
            echo "Adding $IDENTIFIER to haproxy config"
            # Add frontend config
            echo >> "$NEXT_HAPROXY_CONF"
            echo "frontend ${IDENTIFIER}-fe" >> "$NEXT_HAPROXY_CONF"
            {{- range $envAll.Values.conf.haproxy.conf_parts.frontend }}
            echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
            {{- end }}
            {{- range $svc_data.conf_parts.frontend }}
            echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
            {{- end }}
            echo "  default_backend ${IDENTIFIER}-be" >> "$NEXT_HAPROXY_CONF"

            # Add backend config
            echo >> "$NEXT_HAPROXY_CONF"
            echo "backend ${IDENTIFIER}-be" >> "$NEXT_HAPROXY_CONF"
            {{- range $envAll.Values.conf.haproxy.conf_parts.backend }}
            echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
            {{- end }}
            {{- range $svc_data.conf_parts.backend }}
            echo "  {{ . }}" >> "$NEXT_HAPROXY_CONF"
            {{- end }}

            for IP in $SERVICE_IPS; do
                echo "Adding backend $IP:$DEST_PORT"
                echo "  server s$IP $IP:$DEST_PORT" {{ $svc_data.server_opts | quote }} >> "$NEXT_HAPROXY_CONF"
            done
        else
            echo Failed to get destination port for service.
            SUCCESS=0
        fi
    else
        echo Failed to get endpoint IPs for service.
        SUCCESS=0
    fi
    {{- end }}
    {{- end }}
    {{- end }}

    if [ $SUCCESS = 1 ]; then
        mkdir -p $(dirname "$HAPROXY_CONF")
        if ! cmp -s "$HAPROXY_CONF" "$NEXT_HAPROXY_CONF"; then
            if validate_config "$NEXT_HAPROXY_CONF"; then
              echo Replacing HAProxy config file "$HAPROXY_CONF" with:
              cat "$NEXT_HAPROXY_CONF"
              echo
              mv "$NEXT_HAPROXY_CONF" "$HAPROXY_CONF"
            else
              echo "New config failed validation, refusing to replace."
            fi
        else
            echo HAProxy config file unchanged.
        fi
        chmod -R go-rwx $(dirname "$HAPROXY_CONF")
        chown -R $RUNASUSER:$RUNASUSER $(dirname "$HAPROXY_CONF")
        return 0
    fi

    return 1
}

validate_config() {
  file="$1"
  expected_fe="{{- $fe_count -}}"

  count=$(grep -c -E "^frontend" "$file")

  if [ $count -ne $expected_fe ]; then
    echo "Found only $count frontends in config, expected $expected_fe."
    return 1
  else
    return 0
  fi
}

cleanup() {
    cleanup_message_file=$(dirname "$HAPROXY_CONF")/cleanup
    backup_dir=$(dirname "$HAPROXY_CONF")/backup
    mkdir -p $backup_dir
    echo "Starting haproxy-anchor cleanup, files are backed up:" > $cleanup_message_file
    {{- range .Values.conf.anchor.files_to_copy }}
    echo /host{{ .dest }} >> $cleanup_message_file
    mv /host{{ .dest }} $backup_dir
    {{- end }}
    echo "$HAPROXY_CONF" >> $cleanup_message_file
    echo "$NEXT_HAPROXY_CONF" >> $cleanup_message_file
    mv "$HAPROXY_CONF" "$NEXT_HAPROXY_CONF" $backup_dir
}

while true; do
    if [ -e /tmp/stop ]; then
        echo Stopping
        {{- if .Values.conf.anchor.enable_cleanup }}
        cleanup
        {{- end }}
        break
    fi

    if install_config; then
      compare_copy_files
    fi

    sleep {{ .Values.conf.anchor.period }}
done
