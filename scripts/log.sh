#!/bin/bash
echo "Starting DH4 systemd service..."

TOOL_NAME="AEGIR"
TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')
CONFIG_FILE="/etc/${TOOL_LOWER}/${TOOL_LOWER}.conf"

if [ -f "$CONFIG_FILE" ]; then
    # CONF file contains ENV_FILE variable, load it
    export $(grep -v '^#' "$CONFIG_FILE" | xargs)
else
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

if [ -f "$ENV_FILE" ]; then
    # load environment variables from .env file
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    echo "Error: .env file not found at $ENV_FILE - use install.sh to create one"
    exit 1
fi

LOG_FILE="$DATA_DIRECTORY/logs/serialTerm.log"

TERM_SERVICE_FILE="serialTerm@${TOOL_LOWER}.service"
SERIAL_DEVICE="/dev/DH4"

echo "Using serial device: $SERIAL_DEVICE"
echo "Using log file: $LOG_FILE"
while :
do
    
    #printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
    #echo "${current_date_time}: Checking if DH4 serial-getty service is running..."

    NEW_LOOP=0
    while systemctl is-active --quiet "${TERM_SERVICE_FILE}";
    do
        if [ $NEW_LOOP -eq 0 ]; then
            printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
            echo "${current_date_time}: DH4 serial-getty service is running. Waiting for the session to stop..."
            #echo "${current_date_time}: DH4 serial-getty service is running. Stopping it..." >> "$LOG_FILE"
        fi
        printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
        sleep 5
        NEW_LOOP=1
    done

    if [ $NEW_LOOP -eq 1 ]; then
        printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
        echo "${current_date_time}: DH4 serial-getty service is not running. Continuing..."
    fi


    /usr/bin/stty -F "$SERIAL_DEVICE" 921600

    INPUT=$(timeout 5 cat "$SERIAL_DEVICE" 2>/dev/null)

    if [ -n "$INPUT" ]; then
        printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
        #echo "${current_date_time} Received input from \"$SERIAL_DEVICE\". Starting terminal" >> "$LOG_FILE"
        echo "${current_date_time}: Received input from \"$SERIAL_DEVICE\". Starting terminal."
        /usr/local/bin/ran -x 
        /usr/bin/stty -F "$SERIAL_DEVICE" 921600
        systemctl start "$TERM_SERVICE_FILE"
        continue
    fi

    /usr/bin/stty -F "$SERIAL_DEVICE" 115200

    #printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
    #echo "${current_date_time}: No input received from \"$SERIAL_DEVICE\". Starting depthLogger." >> "$LOG_FILE"
    #echo "${current_date_time}: No input received from \"$SERIAL_DEVICE\". Starting depthLogger."
    result=$(timeout 5 /usr/local/bin/depthLogger 2>&1)
    if [ $? -ne 0 ]; then
        printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
        #echo "${current_date_time}: depthLogger failed to start or did not return data." >> "$LOG_FILE"
        echo "${current_date_time}: depthLogger failed to start or did not return data."
        continue
    fi

    echo "$result" >> "$LOG_FILE"
    echo "$result"
    echo "$result" > "$SERIAL_DEVICE"
    
done

echo "Exiting DH4 systemd service script."
printf -v current_date_time '%(%Y-%m-%d %H:%M:%S)T\n' -1
echo "${current_date_time}: Exiting DH4 systemd service script." >> "$LOG_FILE"