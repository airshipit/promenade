Distribution
============

Promenade is using Hyperkube for all Kubernetes components: kubelet, kubectl, etc.
By default Hyperkube binary should be extracted from the image before running Promenade.
This is done by external scripts and is not integrated into Promenade source code.
The other way is to let Promenade do the job and extract binary. This one is more complicated,
needs to share Docker socket inside Promenade container and is optional.

Default behavior
----------------

IMAGE_HYPERKUBE should be exported and set to appropriate value.
Before running build-all CLI for Promenade need to run utility container which will copy binary from image to a shared location.
See tools/g2/stages/build-scripts.sh for reference.


Integrated solution
-------------------

To let Promenade extract binary need to provide more env vars and shared locations for Promenade container.
Also need to enable option --extract-hyperkube in Promenade CLI.

Define var for Docker socket(it should be available for user to read/write):
DOCKER_SOCK="/var/run/docker.sock"

Provide it for container:
-v "${DOCKER_SOCK}:${DOCKER_SOCK}"
-e "DOCKER_HOST=unix:/${DOCKER_SOCK}"

Provide additional var(it's for internal operations):
-e "PROMENADE_TMP_LOCAL=/${PROMENADE_TMP_LOCAL}"
