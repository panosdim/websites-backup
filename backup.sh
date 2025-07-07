#!/bin/bash
# MySQL Docker Backup Script
# Requirements:
# 1. MySQL running in Docker container named "mysql" (or update MYSQL_CONTAINER variable)
# 2. Set MYSQL_ROOT_PASSWORD environment variable with your MySQL root password
#    Example: export MYSQL_ROOT_PASSWORD="your_password"
# 3. Ensure the Docker container is running before executing this script
#
# Uncomment for DEBUG -- START
#set -x
#(
# Uncomment for DEBUG -- END

### Logging Setup ###
LOGFILE="/var/log/backup-sites.log"
exec > >(tee -a "$LOGFILE") 2>&1

### Common Setup ###
BACKUPDIR="/mnt/data/backup"
DATE="$(date +"%d-%b-%Y")"
TIMESTAMP="$(date +"%Y-%m-%d %H:%M:%S")"
TAR="$(which tar)"

echo "[$TIMESTAMP] Starting backup process..."

### MySQL Setup ###
# Docker container name for MySQL (update this to match your container name)
MYSQL_CONTAINER="mysql-db"

#-- Check if backup directory exists --#
if [ ! -d $BACKUPDIR/"$DATE" ]; then
    echo "[$TIMESTAMP] Creating backup directory: $BACKUPDIR/$DATE"
    mkdir -p $BACKUPDIR/"$DATE"
else
    echo "[$TIMESTAMP] Using existing backup directory: $BACKUPDIR/$DATE"
fi

echo "[$TIMESTAMP] Starting MySQL database backup..."

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
        echo "[$TIMESTAMP] Dumping database: $db"
        docker exec -i $MYSQL_CONTAINER mysqldump --defaults-file=/tmp/backup_mysql.cnf --force --opt --no-tablespaces --databases "$db" >"$BACKUPDIR/$DATE/$db.sql"
        if [ $? -eq 0 ]; then
            echo "[$TIMESTAMP] Successfully backed up database: $db"
        else
            echo "[$TIMESTAMP] ERROR: Failed to backup database: $db"
        fi
    fi
done

# Clean up temporary config files
rm -f "$TEMP_CNF"
docker exec -i $MYSQL_CONTAINER rm -f /tmp/backup_mysql.cnf
echo "[$TIMESTAMP] MySQL backup completed."

echo "[$TIMESTAMP] Starting NGINX sites backup..."

#-- Copy NGINX sites --#
for nginx_item in /usr/share/nginx/*; do
    if [[ -d "$nginx_item" ]] && [[ ! "$nginx_item" =~ html$ ]] && [[ ! "$nginx_item" =~ modules$ ]]; then
        echo "[$TIMESTAMP] Copying NGINX site: $nginx_item"
        cp -rf "$nginx_item" "$BACKUPDIR/$DATE"
    fi
done

#-- Copy NGINX sites configurations --#
echo "[$TIMESTAMP] Copying NGINX configurations..."
cp -rf /etc/nginx/conf.d/* $BACKUPDIR/"$DATE"
echo "[$TIMESTAMP] NGINX backup completed."

#-- Compress the folder that contains the databases --#
echo "[$TIMESTAMP] Compressing backup files..."
cd $BACKUPDIR || exit
# Use tar with options to handle file changes gracefully
$TAR --ignore-failed-read --warning=no-file-changed -cjf "$DATE".tar.bz2 "$DATE"
if [ $? -eq 0 ]; then
    echo "[$TIMESTAMP] Successfully created backup archive: $DATE.tar.bz2"
    rm -rf "$DATE"
    echo "[$TIMESTAMP] Removed temporary backup directory"
else
    echo "[$TIMESTAMP] ERROR: Failed to create backup archive"
fi

#-- Delete files and directories older than 30 days --#
echo "[$TIMESTAMP] Cleaning up old backup files (older than 30 days)..."
find $BACKUPDIR -maxdepth 1 -type f -name "*.tar.bz2" -mtime +30 -delete
find $BACKUPDIR -maxdepth 1 -type d -name "*-*-*" -mtime +30 -exec rm -rf {} \;
echo "[$TIMESTAMP] Backup process completed successfully."

# Uncomment for DEBUG -- START
#) 2>&1 | tee /var/log/debug.log
# Uncomment for DEBUG -- END
