#!/bin/bash
{{/*
Copyright 2017 AT&T Intellectual Property.  All other rights reserved.

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

BACKUP_DIR={{ .Values.backup.host_backup_path }}
BACKUP_LOG={{ .Values.backup.backup_log_file | quote }}
NUM_TO_KEEP={{ .Values.backup.no_backup_keep | quote }}
REMOTE_BACKUP_DAYS_TO_KEEP={{ .Values.backup.remote_backup.days_to_keep | quote }}
BACKUP_FILE_NAME={{ .Values.service.name | quote }}
SKIP_BACKUP=0

source /tmp/bin/backup_main.sh

# Export the variables required by the framework
#  Note: REMOTE_BACKUP_ENABLED and CONTAINER_NAME are already exported
export DB_NAMESPACE=${POD_NAMESPACE}
export DB_NAME="etcd"
export LOCAL_DAYS_TO_KEEP=$NUM_TO_KEEP
export REMOTE_DAYS_TO_KEEP=$REMOTE_BACKUP_DAYS_TO_KEEP
export ARCHIVE_DIR=${BACKUP_DIR}/db/${DB_NAMESPACE}/${DB_NAME}/archive

dump_databases_to_directory() {
  set -x
  TMP_DIR=$1
  LOG_FILE=${2:-BACKUP_LOG}

  cd $TMP_DIR
  etcdctl snapshot save --command-timeout=5m $TMP_DIR/$BACKUP_FILE_NAME.$DB_NAMESPACE.all.db >> $LOG_FILE
  BACKUP_RETURN_CODE=$?
  if [[ $BACKUP_RETURN_CODE != 0 ]]; then
    log ERROR $DB_NAME "There was an error backing up the databases." $LOG_FILE
    return $BACKUP_RETURN_CODE
  fi
}

if ! [ -x "$(which etcdctl)" ]; then
  log ERROR $DB_NAME "etcdctl not available, Please use the correct image."
  SKIP_BACKUP=1
fi

if [ ! -d "$BACKUP_DIR" ]; then
  log ERROR $DB_NAME "$BACKUP_DIR doesn't exist, Backup will not continue"
  SKIP_BACKUP=1
fi

if [ $SKIP_BACKUP -eq 0 ]; then
  # Call main program to start the database backup
  backup_databases
else
  log ERROR $DB_NAME "Backup of the ${DB_NAME} database failed. etcd backup failed."
  exit 1
fi
