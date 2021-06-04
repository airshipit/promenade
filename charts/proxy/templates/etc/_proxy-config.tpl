apiVersion: {{ .Values.config_conf.apiVersion | default "kubeproxy.config.k8s.io/v1alpha1"  }}
bindAddress: {{ .Values.config_conf.bindAddress | default "0.0.0.0" }}
bindAddressHardFail: {{ .Values.config_conf.bindAddressHardFail | default "false" }}
clientConnection:
  acceptContentTypes: {{ .Values.config_conf.clientConnection.acceptContentTypes | default "" |quote }}
  burst: {{ .Values.config_conf.clientConnection.burst | default "10" }}
  contentType: {{ .Values.config_conf.clientConnection.contentType | default "application/vnd.kubernetes.protobuf" }}
  kubeconfig: {{ .Values.config_conf.clientConnection.kubeconfig | default "" |quote }}
  qps: {{ .Values.config_conf.clientConnection.qps | default "5" }}
clusterCIDR: {{ .Values.config_conf.clusterCIDR | default "" |quote }}
configSyncPeriod: {{ .Values.config_conf.configSyncPeriod | default "15m0s" }}
conntrack:
  {{- range $key, $val := .Values.config_conf.conntrack }}
  {{ $key }}: {{ $val }}
  {{- end }}
detectLocalMode: {{ .Values.config_conf.detectLocalMode | default "" |quote }}
enableProfiling: {{ .Values.config_conf.enableProfiling | default "false" }}
healthzBindAddress: {{ .Values.config_conf.healthzBindAddress | default "0.0.0.0:10256" }}
hostnameOverride: {{ .Values.config_conf.hostnameOverride | default ""|quote }}
iptables:
  {{- range $key, $val := .Values.config_conf.iptables }}
  {{ $key }}: {{ $val }}
  {{- end }}
ipvs:
  excludeCIDRs: {{ .Values.config_conf.ipvs.excludeCIDRs | default "null" }}
  minSyncPeriod: {{ .Values.config_conf.ipvs.minSyncPeriod | default "0s" }}
  scheduler: {{ .Values.config_conf.ipvs.scheduler | default "" |quote }}
  strictARP: {{ .Values.config_conf.ipvs.strictARP | default "false" }}
  syncPeriod: {{ .Values.config_conf.ipvs.syncPeriod | default "30s" }}
  tcpFinTimeout: {{ .Values.config_conf.ipvs.tcpFinTimeout | default "0s" }}
  tcpTimeout: {{ .Values.config_conf.ipvs.tcpTimeout | default "0s" }}
  udpTimeout: {{ .Values.config_conf.ipvs.udpTimeout | default "0s"  }}
kind: {{ .Values.config_conf.kind | default "KubeProxyConfiguration" }}
metricsBindAddress: {{ .Values.config_conf.metricsBindAddress | default "127.0.0.1:10249" }}
mode: {{ .Values.config_conf.mode | default "iptables"  }}
nodePortAddresses: {{ .Values.config_conf.nodePortAddresses | default "null" }}
oomScoreAdj: {{ .Values.config_conf.oomScoreAdj | default "-999" }}
portRange: {{ .Values.config_conf.portRange | default "" |quote }}
showHiddenMetricsForVersion: {{ .Values.config_conf.showHiddenMetricsForVersion | default "" |quote }}
udpIdleTimeout: {{ .Values.config_conf.udpIdleTimeout | default "250ms" }}
winkernel:
  enableDSR: {{ .Values.config_conf.winkernel.enableDSR | default "false" }}
  networkName: {{ .Values.config_conf.winkernel.networkName | default "" |quote }}
  sourceVip: {{ .Values.config_conf.winkernel.sourceVip | default "" |quote }}
