#!/bin/bash

# Find the script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"


ENV_FILE="$SCRIPT_DIR/.env"

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


# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            echo "Usage: aegir [OPTIONS]"
            echo ""
            echo "aegir is a tool for interfacing with IDS USB3Vision cameras and controlling auto-capture routines."
            echo ""
            echo "Options:"
            echo "  -h, --help              Display this help message and exit"
            echo "  -b, --buffer [size]     Set USB buffer size for this Linux device to [size]mb (default: 1000)"
            echo "  -f, --focus             Test camera focus"
            echo "  -l, --log               View output log of current active process"
            echo "  -n, --node [name]       Get or set value of a device node by name"
            echo "                          Sub-options:"
            echo "                            --get          Get the value of the node"
            echo "                            --set [value]  Set the value of the node to [value]"
            echo "  -q, --query             Check for active aegir process"
            echo "  -r, --routine FILE      Specify a routine file (default directory: ./routines in Aegir DATA_DIRECTORY)"
            echo "  -s, --session           Specify session name"
            echo "  -x, --stop              Send stop signal to currently running process"
            echo "      --run FILE          Run a python script with the environment set up by this tool (advanced users only)"
            echo ""
            echo "Examples:"
            echo "  aegir --buffer 500         Set USB buffer size to 500mb"
            echo "  aegir --focus              Test camera focus"
            echo "  aegir --node \"ExposureTime\" --get"
            echo "                          Get the value of node \"ExposureTime\""
            echo "  aegir --node \"ExposureTime\" --set 1000"
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
                echo "Error: No Node Name. Use 'aegir --node [node name] --get | --set [value]"
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
                echo "Error: No Node Name. Use 'aegir --node [node name] --get | --set [value]'"
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
        *)
            echo "Error: Unknown option $1 - Use aegir -h or --help for commands" >&2
            exit 1
            ;;
    esac
done

#Exit if node command has run
if [ -n "$NODE" ]; then
    exit 0
fi


source activate base
conda activate aegir



if [ -n "$RUN_FOCUS" ]; then
    echo "Running focus test..."
    if [ -n "$RUN_EXEC" ]; then
        $SCRIPT_DIR/python_scripts/dist/aegir --focus
    else
        python "$SCRIPT_DIR/python_scripts/aegir.py" --focus
    fi

    exit 0
fi

if [ -z "$ROUTINE_FILE" ]; then
    echo "Error: Required argument -r/--routine is missing. Use aegir --help for help." >&2
    exit 1
fi

if [ -z "$SESSION_NAME" ]; then
    echo "Error: Required argument -s/--session is missing. Use aegir --help for help." >&2
    exit 1
fi

USB_BUFFER_SIZE="$(cat "$USB_MEMORY_FILE")"

if [ "$USB_BUFFER_SIZE" -lt 1000 ]; then
        echo "Warning: USB buffer size is less than 1000mb. This is likely to cause errors during camera use."
        echo "Please run 'aegir -b' as root to increase the buffer size."
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
        echo "Use 'aegir -x' to stop a currently running process"
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



PYTHON_SCRIPT="$SCRIPT_DIR/python_scripts/auto_capture.py"

# Launch Python script with named arguments

if [ -n "$RUN_EXEC" ]; then
    echo "Running the executable..."
    $SCRIPT_DIR/python_scripts/dist/auto_capture --routine "$ROUTINE_FILE" --session "$SESSION_NAME"  >/dev/null &
else
    python "$PYTHON_SCRIPT" --routine "$ROUTINE_FILE" --session "$SESSION_NAME"  >/dev/null &
fi


disown -h $!


echo "Capture started."

