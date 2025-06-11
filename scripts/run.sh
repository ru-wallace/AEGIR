#!/bin/bash

# Find the script directory
# SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
TOOL_NAME="AEGIR"

TOOL_LOWER="$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')"

CONFIG_FILE="/etc/${TOOL_LOWER}/${TOOL_LOWER}.conf"

if [[ -f "$CONFIG_FILE" ]]
then
    # CONF file contains ENV_FILE variable, load it
    export $(grep -v '^#' "$CONFIG_FILE" | xargs)
else
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi


BASE_DIR="$(dirname "$ENV_FILE")"
AUTOSTART_FILE="/etc/${TOOL_LOWER}/.autostart"

if [ -f "$ENV_FILE" ]
    then # load environment variables from .env file
    export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
    echo "Error: .env file not found in $SCRIPT_DIR/ - use $SCRIPT_DIR/install.sh to create one"
    exit 1
fi

export LD_LIBRARY_PATH="$IDS_PEAK_DIR/lib:$LD_LIBRARY_PATH"
export GENICAM_GENTL64_PATH="$IDS_PEAK_DIR/lib/ids/cti" 
export GENICAM_GENTL32_PATH="$GENICAM_GENTL64_PATH"
export PATH="$IDS_PEAK_DIR/bin:$PATH"

USB_MEMORY_FILE="/sys/module/usbcore/parameters/usbfs_memory_mb"

ROUTINE_FILE=""
SESSION_NAME=""

RED="\e[31m"
GREEN="\e[32m"
LBLUE="\e[94m"
ENDCOLOUR="\e[0m"

query_autostart () {
    if [[ ! -e "$AUTOSTART_FILE" ]]; then
        echo -e "Autostart: ${RED}disabled${ENDCOLOUR}"
        return 0
    fi
    
    ROUTINE=$(sed -n '1{p;q}' "$AUTOSTART_FILE")
    SESSION=$(sed -n '2{p;q}' "$AUTOSTART_FILE")

    if [ -n "$ROUTINE" ]; then
        echo -e "Autostart:  ${LBLUE}enabled${ENDCOLOUR}"
        echo "Routine: $ROUTINE"
    else
        echo "${RED}Error${ENDCOLOUR}: Autostart enabled but routine not set" >&2
        exit 1
    fi

    if [ -n "$SESSION" ]; then
        echo "Session: $SESSION"
    fi

    return 0
}




# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: ${TOOL_LOWER} [OPTIONS]"
            echo ""
            echo "${TOOL_LOWER} is a tool for interfacing with IDS USB3Vision cameras and controlling auto-capture routines."
            echo ""
            echo "Options:"
            echo "  -h, --help                          Display this help message and exit"
            echo "  -b, --buffer [size]                 Set USB buffer size for this Linux device to [size]mb (default: 1000)"
            echo "  -f, --focus                         Test camera focus"
            echo "  -l, --log                           View output log of current active process"
            echo "  -n, --node [name]                   Get or set value of a device node by name"
            echo "                                      Sub-options:"
            echo "                                        --get          Get the value of the node"
            echo "                                        --set [value]  Set the value of the node to [value]"
            echo "  -q, --query                         Check for active ${TOOL_LOWER} process"
            echo "  -r, --routine [routine_name]        Specify a routine file (default directory: ./routines in Aegir DATA_DIRECTORY)"
            echo "  -s, --session [session_name]        Specify session name"
            echo "  -x, --stop                          Send stop signal to currently running process"
            echo "      --run FILE                      Run a python script with the environment set up by this tool (advanced users only)"
            echo "  autostart [OPTIONS]        Manage autostart settings"
            echo "      --enable, -e                  Enable autostart with routine. Requires -r/--routine to be set."
            echo "      --routine, -r [routine_name]  Specify routine file to run on autostart (default directory: ./routines in Aegir DATA_DIRECTORY)"
            echo "      --session, -s [session_name]  Specify session name for autostart routine. If not set, a the starting timestamp will be used."
            echo "      --disable, -d                 Disable autostart"
            echo "      --query, -q                   Query current autostart settings"
            echo "      --start                       Start autostart routine immediately"
        
            echo ""
            echo "Examples:"
            echo "  ${TOOL_LOWER} --buffer 500         Set USB buffer size to 500mb"
            echo "  ${TOOL_LOWER} --focus              Test camera focus"
            echo "  ${TOOL_LOWER} --node \"ExposureTime\" --get"
            echo "                          Get the value of node \"ExposureTime\""
            echo "  ${TOOL_LOWER} --node \"ExposureTime\" --set 1000"
            echo "                          Set the value of node \"ExposureTime\" to 1000 microseconds"
            echo ""
            exit 0
        ;;
        -b|--buffer)
            if [ -n "$2" ]; then
                USB_BUFFER_SIZE="$2"
                shift 2
            else
                USB_BUFFER_SIZE=1000
                shift
            fi
            if [ "$EUID" -eq 0 ]; then
                if [[ "$USB_BUFFER_SIZE" =~ ^[0-9]+$ && "$USB_BUFFER_SIZE" -lt 10000 ]]; then
                    echo "Increasing USB buffer size to 1000mb..."
                    echo "$USB_BUFFER_SIZE" > "$USB_MEMORY_FILE"
                else
                    echo "Error: Invalid buffer size. Buffer size must be an integer below 10000." >&2
                    exit 1
                fi



            else
                echo "Error: Must be root to increase USB buffer size"
                echo "Exiting..."
                exit 1
            fi
            ;;
        -f|--focus)
            RUN_FOCUS=1
            break
            ;;
        -l|--log)
            echo -n "Checking for process..."
            if [ -p "$PIPE_OUT_FILE" ]; then
                AEGIR_STATUS=$(timeout 3 cat "$PIPE_OUT_FILE")
                echo -en "\e[K"
                if [ -z "${AEGIR_STATUS}" ]; then
                    echo -e "\rNo Aegir processes detected"
                else
                    echo -e "\rStatus: $AEGIR_STATUS"
                    AEGIR_SESSION_LINE=$(grep "^Session: " <<< "$AEGIR_STATUS")
                    AEGIR_SESSION="${AEGIR_SESSION_LINE#Session: }" 
                    echo -e "Session: $AEGIR_SESSION"
                    tail -f "$DATA_DIRECTORY/sessions/$AEGIR_SESSION/output.log"
                fi
            else
                echo -e "\rNo Aegir processes detected"
            fi
            exit 0
            ;;
        -n|--node)
            if [ -n "$2" ]; then
                NODE="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --get)
            if [ -n "$NODE" ]; then
                echo "$(ids_devicecommand -n $NODE --get)"
                exit 0
            else
                echo "Error: No Node Name. Use '${TOOL_LOWER} --node [node name] --get | --set [value]"
                exit 1
            fi
            ;;  
        --set)
            if [ -n "$NODE" ]; then
                if [ -n "$2" ]; then
                    NODE="$2"
                    shift 2
                else
                    echo "Error: Argument for $1 is missing" >&2
                    exit 1
            fi
                echo "$(ids_devicecommand -n $NODE --set $VALUE)"
                exit 0
            else
                echo "Error: No Node Name. Use '${TOOL_LOWER} --node [node name] --get | --set [value]'"
                exit 1
            fi
            ;;                      
        -q|--query)
            echo -n "Checking for process..."
            if [ -p "$PIPE_OUT_FILE" ]; then
                AEGIR_STATUS=$(timeout 3 cat "$PIPE_OUT_FILE")
                echo -en "\e[K"
                if [ -z "${AEGIR_STATUS}" ]; then
                    echo -e "\rNo Aegir processes detected"
                else
                    echo -e "\rStatus: $AEGIR_STATUS"
                fi
            else
                echo -e "\rNo Aegir processes detected"
            fi
            exit 0
            ;;
        -r|--routine)
             if [ -n "$2" ]; then
                ROUTINE_FILE="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --run)
            if [ -n "$2" ]; then
                PYTHON_SCRIPT="$2"
                shift 2

                python "$PYTHON_SCRIPT" "$@"
                exit 0
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        -s|--session)
             if [ -n "$2" ]; then
                SESSION_NAME="$2"
                shift 2
            else
                echo "Error: Argument for $1 is missing" >&2
                exit 1
            fi
            ;;
        --exec)
            RUN_EXEC=1
            shift
            ;;
        -x|--stop)
            echo -n "Checking for process..."
            if ! [ -p "$PIPE_OUT_FILE" ]; then
                echo -e "\rNo Aegir processes detected"
                exit 0
            fi
            AEGIR_STATUS=$(timeout 3 cat "$PIPE_OUT_FILE")
            if [ -z "${AEGIR_STATUS}" ]; then
                echo -e "\rNo Aegir processes detected"
                exit 0
            fi
            echo -e "\rProcess found:\e[K"
            echo "$AEGIR_STATUS"
            echo "Stopping Process..."
            echo -n "STOP" > "$PIPE_IN_FILE" &
            sleep .5
            STOP_STATUS=$(timeout 3 cat "$PIPE_OUT_FILE")

            echo "Stopping: $STOP_STATUS"
            if [ "$STOP_STATUS" = "STOPPING" ]; then
                echo "Process Successfully Stopped"
            else
                echo "Failed to stop process"
                exit 0
            fi
            exit 0
            ;;

        autostart)
            if [ -n "$2" ]; then
                case "$2" in
                    --enable|-e)
                        AUTOSTART=true
                        shift 2
                        ;;
                    --disable|-d)
                        AUTOSTART=false
                        shift 2
                        ;;
                    --query|-q)
                        query_autostart
                        shift 2
                        exit
                        ;;
                    --start)
                        AUTOSTART_RUN=true
                        shift 2
                        ;;
                    *)
                        echo "Error: Unknown autostart option $1 - Use ${TOOL_LOWER} -h or --help for commands" >&2
                        shift
                        exit 1

                        ;;
                esac
            else 
                query_autostart
                shift
                exit

            fi
            ;;
        *)
            echo "Error: Unknown option $1 - Use ${TOOL_LOWER} -h or --help for commands" >&2
            exit 1
            ;;
    esac
done

#Exit if node command has run
if [ -n "$NODE" ]; then
    exit 0
fi



if [ -n "$RUN_FOCUS" ]; then
    echo "Running focus test..."
    if [ -n "$RUN_EXEC" ]; then
        $SCRIPT_DIR/python_scripts/dist/${TOOL_LOWER} --focus
    else
        "$PYTHON_EXECUTABLE" "$SCRIPT_DIR/python_scripts/${TOOL_LOWER}.py" --focus
    fi

    exit 0
fi

#Enable or disable autostart
# If enabling, check routine file/name is specified and warn+exit if not
# Enabling autostart creates '.autostart' file in script dir with name of routine to run
if [ -n "$AUTOSTART" ]; then
    if [ "$AUTOSTART" = true ]; then
        if [ -z "$ROUTINE_FILE" ]; then
            echo "Error: Required argument -r/--routine is missing. Use ${TOOL_LOWER} --help for help." >&2
            exit 1
        fi

        echo "$ROUTINE_FILE" > "$AUTOSTART_FILE"

        echo "Enabling Autostart with params:"
        echo "Routine: $ROUTINE_FILE"
        if [ -n "$SESSION_NAME" ]; then
            echo "$SESSION_NAME" >> "$AUTOSTART_FILE"
            echo "Session Name: $SESSION_NAME"
        fi
    else
        echo "Disabling Autostart"
        rm -f "$AUTOSTART_FILE"
    fi

    exit 0
fi


if [[ -n "$AUTOSTART_RUN" && -e "$AUTOSTART_FILE" ]]; then

    echo "Running autostart routine from file: $AUTOSTART_FILE"
    echo "Waiting 10 seconds before starting."
    echo "If a terminal session starts, the routine will not automatically start."
    sleep 10

    if systemctl is-active --quiet "serialTerm@${TOOL_LOWER}.service"; then
        echo "Serial terminal service is running. Automatic routine start will not occur."
        exit 0
    fi
    ROUTINE_FILE=$(sed -n '1{p;q}' "$AUTOSTART_FILE")
    SESSION_NAME=$(sed -n '2{p;q}' "$AUTOSTART_FILE")

    
    echo "No terminal session detected, starting routine: $ROUTINE_FILE"


fi
    

if [ -z "$ROUTINE_FILE" ]; then
    echo "Error: Required argument -r/--routine is missing. Use ${TOOL_LOWER} --help for help." >&2
    exit 1
fi


USB_BUFFER_SIZE="$(cat "$USB_MEMORY_FILE")"

if [ "$USB_BUFFER_SIZE" -lt 1000 ]; then
        echo "Warning: USB buffer size is less than 1000mb. This is likely to cause errors during camera use."
        echo "Please run '${TOOL_LOWER} -b' as root to increase the buffer size."
fi


echo -n "Checking for already running process..."
if [ -p "$PIPE_OUT_FILE" ]; then
    AEGIR_STATUS=$(timeout 3 cat "$PIPE_OUT_FILE")
    echo -en "\e[K"
    if [ -z "${AEGIR_STATUS}" ]; then
        echo -e "\rNo Aegir processes detected            "
    else
        echo -e "\rAegir process already running:         "
        echo "$AEGIR_STATUS"
        echo "Use '${TOOL_LOWER} -x' to stop a currently running process"
        echo "Exiting..."
        exit 1
    fi
else
    echo -e "\rNo Aegir processes detected            "
fi



#For setting up IDS Peak libraries
#export LD_LIBRARY_PATH="/opt/ids-peak-with-ueyetl_2.7.1.0-16417_arm64/lib:$LD_LIBRARY_PATH"  &> /dev/null
#export GENICAM_GENTL64_PATH="/opt/ids-peak-with-ueyetl_2.7.1.0-16417_arm64/lib/ids/cti"  &> /dev/null
#export GENICAM_GENTL32_PATH="/opt/ids-peak-with-ueyetl_2.7.1.0-16417_arm64/lib/ids/cti"  &> /dev/null


PYTHON_SCRIPT="$BASE_DIR/python_scripts/${TOOL_LOWER}.py"

# Launch Python script with named arguments


# if [ -n "$RUN_EXEC" ]; then
#     echo "Running the executable..."
#     $SCRIPT_DIR/python_scripts/dist/auto_capture --routine "$ROUTINE_FILE" --session "$SESSION_NAME" "$AUTOSTART_ARG"  >/dev/null &
if [ -n "$AUTOSTART_RUN" ]; then
    "$PYTHON_EXECUTABLE" "$PYTHON_SCRIPT" --routine "$ROUTINE_FILE" --session "$SESSION_NAME" --autostart >/dev/null &
else
    "$PYTHON_EXECUTABLE" "$PYTHON_SCRIPT" --routine "$ROUTINE_FILE" --session "$SESSION_NAME" >/dev/null &
fi


disown -h $!


echo "Capture started."

