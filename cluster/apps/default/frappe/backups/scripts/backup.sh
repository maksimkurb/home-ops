#!/usr/bin/env bash

set -euo pipefail

: "${SITE_NAME:?SITE_NAME is required}"
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

cd /home/frappe/frappe-bench

retention_hours=$((BACKUP_RETENTION_DAYS * 24))
retention_minutes=$((retention_hours * 60))
bench set-config -gp keep_backups_for_hours "${retention_hours}"

echo "Creating database, site configuration, public files, and private files backups for ${SITE_NAME}"
bench --site "${SITE_NAME}" backup --with-files

backup_dir="/home/frappe/frappe-bench/sites/${SITE_NAME}/private/backups"
echo "Removing local backups older than ${BACKUP_RETENTION_DAYS} days"
find "${backup_dir}" -type f -mmin "+${retention_minutes}" -delete

echo "Frappe backup completed successfully"
