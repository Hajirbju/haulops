#!/usr/bin/env sh
# Backup database HAULOPS (pg_dump terkompres). Jalankan dari root repo di VPS:
#   sh deploy/backup.sh
# Jadwalkan harian lewat cron, mis.:
#   0 2 * * * cd /opt/haulops && sh deploy/backup.sh >> /var/log/haulops-backup.log 2>&1
# Hasil: deploy/backups/haulops-YYYYmmdd-HHMMSS.sql.gz (14 file terakhir disimpan).
set -eu

# Compose butuh variabel dari deploy/.env (POSTGRES_PASSWORD, dst.).
export COMPOSE_FILE=docker-compose.prod.yml COMPOSE_ENV_FILES=deploy/.env

mkdir -p deploy/backups
FILE="deploy/backups/haulops-$(date +%Y%m%d-%H%M%S).sql.gz"

docker compose exec -T db \
  pg_dump -U haulops -d haulops --no-owner --no-privileges | gzip > "$FILE"

echo "Backup selesai: $FILE ($(du -h "$FILE" | cut -f1))"

# Simpan 14 backup terbaru saja.
ls -1t deploy/backups/haulops-*.sql.gz | tail -n +15 | xargs -r rm --
