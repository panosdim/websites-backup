#!/bin/sh
if [ "$(id -u)" != "0" ]; then
    exec sudo bash "$0" "$@"
fi

is_service_exists() {
    x="$1"
    if systemctl status "${x}" 2>/dev/null | grep -Fq "Active:"; then
        return 0
    else
        return 1
    fi
    unset x
}

INSTALL_PATH=/opt/backup
SYSTEMD_PATH=/etc/systemd/system
EXEC_NAME=backup
SERVICE_FILE=$EXEC_NAME.service
TIMER_FILE=$EXEC_NAME.timer
CNF_FILE=mysql.cnf

# Check if needed files exist
if [ -f $CNF_FILE ] && [ -f $TIMER_FILE ] && [ -f "$EXEC_NAME.sh" ] && [ -f $SERVICE_FILE ]; then
    # Check if we upgrade or install for first time
    if is_service_exists "$TIMER_FILE"; then
        systemctl stop $TIMER_FILE
        cp $EXEC_NAME $INSTALL_PATH
        cp $CNF_FILE $INSTALL_PATH
        systemctl start $TIMER_FILE
    else
        mkdir -p $INSTALL_PATH
        cp $EXEC_NAME $INSTALL_PATH
        cp $CNF_FILE $INSTALL_PATH
        cp $SERVICE_FILE $SYSTEMD_PATH
        cp $TIMER_FILE $SYSTEMD_PATH
        systemctl start $TIMER_FILE
        systemctl enable $TIMER_FILE
    fi
else
    echo "Not all needed files found. Installation failed."
    exit 1
fi
