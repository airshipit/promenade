[crio.image]
pause_image = {{ .Values.images.tags.pause | quote }}

[crio.runtime]
cgroup_manager = "systemd"
