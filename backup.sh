#!/bin/bash
# Uncomment for DEBUG -- START
#set -x
#(
# Uncomment for DEBUG -- END

### Common Setup ###
BACKUPDIR="/mnt/data/backup"
DATE="$(date +"%d-%b-%Y")"
TAR="$(which tar)"

### MySQL Setup ###
MYSQL="$(which mysql)"
CNF="mysql.cnf"
MYSQLDUMP="$(which mysqldump)"

#-- Check if backup directory exists --#
if [ ! -d $BACKUPDIR/"$DATE" ]; then
    mkdir -p $BACKUPDIR/"$DATE"
fi

#-- Dump databases into SQL files --#
exclude_dbs='information_schema|mysql|performance_schema|sys'
databases=$($MYSQL --defaults-file=$CNF -e "SHOW DATABASES;" | grep -v -E '^('$exclude_dbs')$' | tr -d "| " | grep -v Database)

for db in $databases; do
    if [[ "$db" != "information_schema" ]] && [[ "$db" != _* ]]; then
        echo "Dumping database: $db"
        $MYSQLDUMP --defaults-file=$CNF --force --opt --no-tablespaces --databases "$db" >$BACKUPDIR/"$DATE"/"$db".sql
    fi
done

#-- Compress the folder that contains the databases --#
cd $BACKUPDIR || exit
$TAR cjfP "$DATE".tar.bz2 "$DATE"
rm -rf "$DATE"

#-- Delete files older than 180 days --#
find $BACKUPDIR/* -mtime +180 -exec rm -f {} \;

# Uncomment for DEBUG -- START
#) 2>&1 | tee /home/stockroo/bin/debug.log
# Uncomment for DEBUG -- END
