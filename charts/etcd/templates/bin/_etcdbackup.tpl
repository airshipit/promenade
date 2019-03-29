#!/bin/sh
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
set -ex
BACKUP_DIR="/var/lib/etcd/backup"
BACKUP_LOG={{ .Values.backup.backup_log_file | quote }}
NUM_TO_KEEP={{ .Values.backup.no_backup_keep | quote }}
BACKUP_FILE_NAME={{ .Values.service.name | quote }}
SKIP_BACKUP=0

etcdbackup() {
  etcdctl snapshot save $BACKUP_DIR/$(BACKUP_FILE_NAME)-backup-$(date +"%m-%d-%Y-%H-%M-%S").db >> $BACKUP_LOG
  BACKUP_RETURN_CODE=$?
  if [[ $BACKUP_RETURN_CODE != 0 ]]; then
    echo "There was an error backing up the databases. Return code was $BACKUP_RETURN_CODE."
    exit $BACKUP_RETURN_CODE
  fi
  LATEST_BACKUP=`ls -t $BACKUP_DIR | head -1`
  echo "Archiving $LATEST_BACKUP..."
  cd $BACKUP_DIR
  tar -czf $BACKUP_DIR/$LATEST_BACKUP.tar.gz $LATEST_BACKUP
  rm -rf $LATEST_BACKUP
  echo "Clearing earliest backups..."
  NUM_LOCAL_BACKUPS=`ls -ld $BACKUP_DIR | wc -l`
  while [ $NUM_LOCAL_BACKUPS -gt $NUM_TO_KEEP ]
  do
    EARLIEST_BACKUP=`ls -tr $BACKUP_DIR | head -1`
    echo "Deleting $EARLIEST_BACKUP..."
    rm -rf "$BACKUP_DIR/$EARLIEST_BACKUP"
    NUM_LOCAL_BACKUPS=`ls -ld $BACKUP_DIR | wc -l`
  done
}

if ! [ -x "$(which etcdctl)" ]; then
  echo "ERROR: etcdctl not available, Please use the correct image."
  SKIP_BACKUP=1
fi

if [ ! -d "$BACKUP_DIR" ]; then
  echo "ERROR: $BACKUP_DIR doesn't exist, Backup will not continue"
  SKIP_BACKUP=1
fi

if [ $SKIP_BACKUP == '0' ]; then
  etcdbackup
else
  echo "Error: etcd backup failed."
  exit 1
fi
