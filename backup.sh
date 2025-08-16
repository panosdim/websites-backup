#!/bin/bash
# Uncomment for DEBUG -- START
#set -x
#(
# Uncomment for DEBUG -- END

### Logging Setup ###
LOGFILE="/var/log/backup-data.log"
exec > >(tee -a "$LOGFILE") 2>&1

log() {
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*"
}

### Common Setup ###
BACKUPDIR="/mnt/data/backup"
DATE="$(date +"%d-%b-%Y")"
TAR="$(which tar)"

log "Starting backup process..."

### MySQL Setup ###
# Docker container name for MySQL (update this to match your container name)
MYSQL_CONTAINER="mysql-db"

#-- Check if backup directory exists --#
if [ ! -d $BACKUPDIR/"$DATE" ]; then
    log "Creating backup directory: $BACKUPDIR/$DATE"
    mkdir -p $BACKUPDIR/"$DATE"
else
    log "Using existing backup directory: $BACKUPDIR/$DATE"
fi

log "Starting MySQL database backup..."

#-- Dump databases into SQL files --#
exclude_dbs='information_schema|mysql|performance_schema|sys'

# Create temporary MySQL config file for secure authentication
TEMP_CNF="/tmp/backup_mysql.cnf"
cat >"$TEMP_CNF" <<EOF
[client]
user=root
password=${MYSQL_ROOT_PASSWORD:-}
EOF

# Copy config file to Docker container
docker cp "$TEMP_CNF" "$MYSQL_CONTAINER:/tmp/backup_mysql.cnf"

# Get databases list using config file
databases=$(docker exec -i $MYSQL_CONTAINER mysql --defaults-file=/tmp/backup_mysql.cnf -e "SHOW DATABASES;" | grep -v -E '^('$exclude_dbs')$' | tr -d "| " | grep -v Database)

for db in $databases; do
    if [[ "$db" != "information_schema" ]] && [[ "$db" != _* ]]; then
        log "Dumping database: $db"
        docker exec -i $MYSQL_CONTAINER mysqldump --defaults-file=/tmp/backup_mysql.cnf --force --opt --no-tablespaces --databases "$db" >"$BACKUPDIR/$DATE/$db.sql"
        if [ $? -eq 0 ]; then
            log "Successfully backed up database: $db"
        else
            log "ERROR: Failed to backup database: $db"
        fi
    fi
done

# Clean up temporary config files
rm -f "$TEMP_CNF"
docker exec -i $MYSQL_CONTAINER rm -f /tmp/backup_mysql.cnf
log "MySQL backup completed."

log "Starting NGINX sites backup..."

#-- Copy NGINX sites --#
for nginx_item in /usr/share/nginx/*; do
    if [[ -d "$nginx_item" ]] && [[ ! "$nginx_item" =~ html$ ]] && [[ ! "$nginx_item" =~ modules$ ]]; then
        log "Copying NGINX site: $nginx_item"
        cp -rf "$nginx_item" "$BACKUPDIR/$DATE"
    fi
done

#-- Copy NGINX sites configurations --#
log "Copying NGINX configurations..."
cp -rf /etc/nginx/conf.d/* $BACKUPDIR/"$DATE"
log "NGINX backup completed."

#-- Compress the folder that contains the databases --#
log "Compressing backup files..."
cd $BACKUPDIR || exit
# Use tar with options to handle file changes gracefully
$TAR --ignore-failed-read --warning=no-file-changed -cjf "$DATE".tar.bz2 "$DATE"
if [ $? -eq 0 ]; then
    log "Successfully created backup archive: $DATE.tar.bz2"
    rm -rf "$DATE"
    log "Removed temporary backup directory"
else
    log "ERROR: Failed to create backup archive"
fi

#-- Delete files and directories older than 180 days --#
log "Cleaning up old backup files (older than 180 days)..."
find $BACKUPDIR -maxdepth 1 -type f -name "*.tar.bz2" -mtime +180 -delete
find $BACKUPDIR -maxdepth 1 -type d -name "*-*-*" -mtime +180 -exec rm -rf {} \;


#-- Rsync folder to a remote server --#
SRC_DIR="/mnt/data/backup"
DEST_DIR="root@spiti.hopto.org:/mnt/storage/Oracle-Backup"
SSH_PORT="3022"
SSH_KEY="/home/opc/.ssh/id_rsa"

log "Starting rsync backup"
RSYNC_CMD="rsync -rlptDvz \
      -e \"ssh -p $SSH_PORT -i $SSH_KEY -o ServerAliveInterval=60 -o ServerAliveCountMax=5 -o ExitOnForwardFailure=yes\" \
      --no-perms --no-owner --no-group \
      --delete-after --delete-excluded \
      --checksum \
      \"$SRC_DIR\" \"$DEST_DIR\""

# Retry loop for rsync (3 attempts)
for attempt in 1 2 3; do
    log "Rsync attempt $attempt..."
    eval $RSYNC_CMD
    RSYNC_EXIT_CODE=$?
    if [ $RSYNC_EXIT_CODE -eq 0 ]; then
        log "✅ Rsync backup completed successfully"
        curl -fsS --retry 3 "$HEALTHCHECK_URL" > /dev/null
        break
    else
        log "⚠️ Rsync attempt $attempt failed with code $RSYNC_EXIT_CODE"
        sleep 30
    fi
done

if [ $RSYNC_EXIT_CODE -ne 0 ]; then
    log "❌ Rsync backup failed after 3 attempts"
    curl -fsS --retry 3 "${HEALTHCHECK_URL}/fail" > /dev/null
fi
log "Finished rsync backup"

log "Backup process completed successfully."

# Uncomment for DEBUG -- START
#) 2>&1 | tee /var/log/debug.log
# Uncomment for DEBUG -- END
