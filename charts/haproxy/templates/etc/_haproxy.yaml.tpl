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
---
apiVersion: v1
kind: Pod
metadata:
  name: haproxy
  namespace: {{ .Release.Namespace }}
  labels:
{{ tuple $envAll "haproxy" "server" | include "helm-toolkit.snippets.kubernetes_metadata_labels" | indent 4 }}
  annotations:
    {{ tuple $envAll | include "helm-toolkit.snippets.release_uuid" }}
{{ dict "envAll" $envAll "podName" "haproxy" "containerNames" (list "haproxy") | include "helm-toolkit.snippets.kubernetes_mandatory_access_control_annotation" | indent 4 }}
spec:
{{ dict "envAll" $envAll "application" "server" | include "helm-toolkit.snippets.kubernetes_pod_security_context" | indent 2 }}
  hostNetwork: true
  containers:
    - name: haproxy
      image: {{ .Values.images.tags.haproxy }}
      imagePullPolicy: {{ .Values.images.pull_policy }}
{{ tuple . .Values.pod.resources.haproxy_pod | include "helm-toolkit.snippets.kubernetes_resources" | indent 6 }}
{{ dict "envAll" $envAll "application" "server" "container" "haproxy" | include "helm-toolkit.snippets.kubernetes_container_security_context" | indent 6 }}
      hostNetwork: true
      env:
        - name: HAPROXY_CONF
          value: {{ .Values.conf.haproxy.container_config_dir }}/haproxy.cfg
        - name: LIVE_HAPROXY_CONF
          value: /tmp/live_haproxy.cfg
        - name: STAGE_HAPROXY_CONF
          value: /tmp/stage_haproxy.cfg
      command:
        - /bin/sh
        - -c
        - |
            set -eux

            test_conf () {
              if [ ! -s "$HAPROXY_CONF" ]; then
                 echo "New proposed config not found at $HAPROXY_CONF"
                 return 1
              fi
              # this is a safety gate to avoid a race of the anchor
              # changing a possible new config between the validation
              # and installation
              echo "Staging proposed config for installation."
              cp "$HAPROXY_CONF" "$STAGE_HAPROXY_CONF"
              if ! haproxy -c -f "$STAGE_HAPROXY_CONF"; then
                echo "Proposed config not valid."
                return 1
              fi
              return 0
            }

            while ! test_conf; do
                sleep 1
            done

            echo vvv Starting with initial config vvv
            cat "$STAGE_HAPROXY_CONF"
            echo
            mv "$STAGE_HAPROXY_CONF" "$LIVE_HAPROXY_CONF"
            chmod 700 "$LIVE_HAPROXY_CONF"

            # NOTE(mark-burnett): sleep for clearer log output
            sleep 1

            haproxy -D -f "$LIVE_HAPROXY_CONF" -p /tmp/haproxy.pid

            echo HAProxy started, monitoring for config changes..

            set +x
            while true; do
                if ! cmp -s "$HAPROXY_CONF" "$LIVE_HAPROXY_CONF"; then
                    if ! test_conf; then
                      echo New config file appears invalid, refusing to replace.
                    else
                      echo vvv Replacing old config vvv
                      cat "$LIVE_HAPROXY_CONF"
                      echo

                      echo vvv With new config vvv
                      cat "$STAGE_HAPROXY_CONF"
                      echo

                      cp "$STAGE_HAPROXY_CONF" "$LIVE_HAPROXY_CONF"

                      # NOTE(mark-burnett): sleep for clearer log output
                      sleep 1

                      set -x
                      haproxy -D -f "$LIVE_HAPROXY_CONF" -p /tmp/haproxy.pid \
                          -x /tmp/haproxy.sock \
                          -sf $(cat /tmp/haproxy.pid)
                      set +x
                    fi
                fi
                sleep {{ .Values.conf.haproxy.period }}
            done

      volumeMounts:
        - name: etc
          mountPath: {{ .Values.conf.haproxy.container_config_dir }}
          readOnly: True
  volumes:
    - name: etc
      hostPath:
        path: {{ .Values.conf.haproxy.host_config_dir }}
{{ dict "envAll" $envAll "application" "haproxy" | include "helm-toolkit.snippets.kubernetes_pod_security_context" | indent 2 }}
