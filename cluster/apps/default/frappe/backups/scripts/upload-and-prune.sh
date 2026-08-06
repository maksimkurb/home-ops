#!/bin/sh

set -eu

: "${SITE_NAME:?SITE_NAME is required}"
: "${S3_ENDPOINT:?S3_ENDPOINT is required}"
: "${S3_BUCKET:?S3_BUCKET is required}"
: "${MINIO_ACCESS_KEY:?MINIO_ACCESS_KEY is required}"
: "${MINIO_SECRET_KEY:?MINIO_SECRET_KEY is required}"
: "${BACKUP_RETENTION_DAYS:?BACKUP_RETENTION_DAYS is required}"

case "${BACKUP_RETENTION_DAYS}" in
  ''|*[!0-9]*)
    echo "BACKUP_RETENTION_DAYS must be a positive integer" >&2
    exit 1
    ;;
  0)
    echo "BACKUP_RETENTION_DAYS must be greater than zero" >&2
    exit 1
    ;;
esac

backup_dir="/home/frappe/frappe-bench/sites/${SITE_NAME}/private/backups"
remote="backup/${S3_BUCKET}/${SITE_NAME}"

if [ ! -d "${backup_dir}" ]; then
  echo "Backup directory does not exist: ${backup_dir}" >&2
  exit 1
fi

mc alias set backup "${S3_ENDPOINT}" "${MINIO_ACCESS_KEY}" "${MINIO_SECRET_KEY}"
mc mb --ignore-existing "backup/${S3_BUCKET}"

echo "Uploading Frappe backups to ${remote}"
mc mirror --overwrite "${backup_dir}/" "${remote}/"

echo "Removing remote backups older than ${BACKUP_RETENTION_DAYS} days"
mc rm \
  --recursive \
  --force \
  --older-than "${BACKUP_RETENTION_DAYS}d" \
  "${remote}/"

echo "Upload and retention cleanup completed successfully"
