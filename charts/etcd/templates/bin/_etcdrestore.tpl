#!/bin/bash

#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# Capture the user's command line arguments
ARGS=("$@")

source /tmp/restore_main.sh

# Export the variables needed by the framework
export DB_NAME="etcd"
export DB_NAMESPACE=${POD_NAMESPACE}
export SINGLE_DB_NAME_DIR=${ETCD_BACKUP_BASE_PATH}/db/${DB_NAMESPACE}/${DB_NAME}/archive

# Extract all databases from an archive and put them in the requested
# file.
get_databases() {
  TMP_DIR=$1
  DB_FILE=$2

  ETCD_FILE={{ .Values.service.name }}.$POD_NAMESPACE.all.db
  if [[ -e $TMP_DIR/$ETCD_FILE ]]; then
    grep 'CREATE DATABASE' $TMP_DIR/$ETCD_FILE | awk '{ print $3 }' > $DB_FILE
  else
    # no databases - just touch the file
    touch $DB_FILE
  fi
}

restore_single_db() {
  set -x
  SINGLE_DB_NAME=$1
  TMP_DIR=$2
  ANCHOR_POD=$SINGLE_DB_NAME
  if [[ -f $TMP_DIR/$ETCD_FILE ]]; then

       # Check etcd-anchor pod
       if [[ ! $(kubectl get pods -n $POD_NAMESPACE $ANCHOR_POD) ]]; then
         echo "Could not find pod $ANCHOR_POD."
         return 1
       fi

       # Copy backup to etcd-anchor
       kubectl cp -n $POD_NAMESPACE $TMP_DIR/$ETCD_FILE $ANCHOR_POD:/
       if [[ $? -ne 0 ]]; then
         echo "Could not copy backup to $ANCHOR_POD."
         return 1
       fi

       # Node Name
       NAME=$(kubectl get pods -n $POD_NAMESPACE $ANCHOR_POD -o jsonpath={.spec.nodeName})

       # Initial Cluster
       INITIAL_CLUSTER="$(etcdctl member list|awk -F , '{gsub (" ", "", $0);printf "%s=%s,", $3,$4}')"
       INITIAL_ADVERTISE_PEER_URLS=$(kubectl exec -it -n $POD_NAMESPACE $ANCHOR_POD -- env| grep PEER |awk -F = '{print $2}')

       # Restore snapshot
       kubectl exec -it -n $POD_NAMESPACE $ANCHOR_POD -- env ETCD_FILE=$ETCD_FILE NAME=$NAME INITIAL_CLUSTER=$INITIAL_CLUSTER INITIAL_ADVERTISE_PEER_URLS=$INITIAL_ADVERTISE_PEER_URLS;/usr/local/bin/etcdctl snapshot restore $ETCD_FILE --name $NAME --initial-cluster "$INITIAL_CLUSTER" --initial-cluster-token=kubernetes-etcd-init-token --initial-advertise-peer-urls "${INITIAL_ADVERTISE_PEER_URLS}"
       if [[ $? -ne 0 ]]; then
         echo "Could not restore snapshot from $ETCD_FILE."
         return 1
       fi

       # backup etcd host data to /tmp
       cp -rf {{ .Values.etcd.host_data_path }} /tmp

       # Remove {{ .Values.etcd.host_data_path }}
       rm -rf {{ .Values.etcd.host_data_path }}

       # Copy snapshot to {{ .Values.etcd.host_data_path }}
       cp -rf $NAME.etcd/member/ {{ .Values.etcd.host_data_path }}
       if [[ $? -ne 0 ]]; then
         echo "Could not copy snapshot to $NAME."
         return 1
       fi

       # Delete etcd anchor pod
       kubectl delete pods -n $POD_NAMESPACE $ANCHOR_POD
       if [[ $? -ne 0 ]]; then
         echo "Could not delete $ANCHOR_POD pod."
         return 1
       fi

       # Check for pod status
       kubectl wait -n $POD_NAMESPACE --timeout=15m --for condition=ready pods -l 'application={{ .Values.service.name | replace "-etcd" "" }},component in (etcd,etcd-anchor)'
       if [[ $? -eq 0 ]]; then
         echo "Database restore Successful."
       else
         echo "Database restore Failed."
         return 1
       fi

  else
    echo "No database file available to restore from."
    return 1
  fi
  return 0
}

# Call the CLI interpreter, providing the archive directory path and the
# user arguments passed in
cli_main ${ARGS[@]}
