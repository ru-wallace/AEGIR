#!/bin/bash


TOOL_NAME="AEGIR"
TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')

CONFIG_FILE="/etc/${TOOL_LOWER}/${TOOL_LOWER}.conf"

if [ -f "$CONFIG_FILE" ]
then
    # CONF file contains ENV_FILE variable, load it
    export $(grep -v '^#' "$CONFIG_FILE" | xargs)
else
    echo "Error: Configuration file $CONFIG_FILE not found."
    exit 1
fi

if [ -f "$ENV_FILE" ]
    then # load environment variables from .env file
    export $(grep -v '^#' "$ENV_FILE" | xargs)
    else
    echo "Error: .env file not found at $ENV_FILE - use install.sh to create one"
    exit 1
fi


if [ -z "$DATA_DIRECTORY" ]; then
    echo "Error: DATA_DIRECTORY is not set in $ENV_FILE"
    exit 1
fi

SESSION_DIR="$DATA_DIRECTORY/sessions"

# Check if the data directory exists
if [ ! -d "$SESSION_DIR" ]; then
    echo "Error: Session directory $SESSION_DIR does not exist."
    exit 1
fi


###################################################################
######################## Process Arguments ########################
###################################################################

show_help() {
    echo "${TOOL_LOWER}Sesh.sh - Display ${TOOL_NAME} sessions"
    echo ""
    echo "Display a list of sessions in the ${TOOL_NAME} session directory."
    echo ""
    echo "Sessions are output separated by newlines in the format:"
    echo "  'session_name, session_date, n_measurements'"
    echo ""
    echo "By default the script will display all sessions in order from oldest to newest."
    echo ""
    echo "Usage: $0 [-n NUM_SESSIONS] [-r] [-o]"
    echo ""
    echo "Options:"
    echo "  -h               Display this help message"
    echo "  -n NUM_SESSIONS  Specify the number of sessions to display (default: all)"
    echo "                      The program will display the most recent NUM_SESSIONS sessions,"
    echo "                      or the oldest NUM_SESSIONS sessions if -o is specified."
    echo "  -r               Reverse the order of the sessions."
    echo "                      (i.e order from newest to oldest)"
    echo "  -o               Output the oldest NUM_SESSIONS sessions."
    echo "                      (Still ordered from oldest to newest unless -r is also specified)"
    echo "  -c               Output just the count of sessions which match the criteria."
    echo "                      (i.e. the number of sessions which would be output by the script)"
    echo "  -m               Output the session names only, separated by DELIMITER (default: space)"
    echo "  -d DELIMITER     Specify the delimiter to use when outputting session names only (default: space)"
    exit 0
}


OPTSTRING=":n:rohcmd:"

while getopts "$OPTSTRING" opt; do
    case $opt in
        n) # Number of sessions to display
            NUM_SESSIONS="$OPTARG"
            if ! [[ "$NUM_SESSIONS" =~ ^[0-9]+$ ]]; then
                echo "Error: -n option requires a numeric argument."
                exit 1
            fi
            ;;
        r) # Reverse order
            REVERSE_ORDER=true
            ;;
        o) # Output oldest sessions
            OLD_SESSIONS=true
            ;;
        h) # Help
            show_help
            ;;
        c) # Count sessions matching criteria
            COUNT_SESSIONS=true
            ;;
        d) # Delimiter for session names only
            DELIMITER="$OPTARG"
            if [ -z "$DELIMITER" ]; then
                DELIMITER=" " # Default delimiter is space
            fi
            ;;
        m) # Output session names only
            SESSION_NAMES_ONLY=true
            DELIMITER="${DELIMITER:- }" # Default delimiter is space if not set
            ;;
        \:) # Missing option argument
            echo "Error: Option -$OPTARG requires an argument."
            show_help
            ;;
        \?) # Invalid option
            echo "Error: Invalid option -$OPTARG"
            show_help
            ;;
    esac
done



process_session() {
    local session="$1"
    local info_file="$session/info.yml"
    if [ -f "$info_file" ]; then
        local session_name=""
        local session_date=""
        local session_n_measurements=""
        while IFS= read -r line; do
            if [[ "$line" == "name"* ]]; then
                session_name=$(echo "$line" | awk '{print $2}')            
            elif [[ "$line" == "date:"* ]]; then
                session_date=$(echo "$line" | awk '{print $2, $3}') # Assuming date is in the format "YYYY-MM-DD HH:MM:SS"
            elif [[ "$line" == "n_measurements:"* ]]; then
                session_n_measurements=$(echo "$line" | awk '{print $2}')
            fi

            if [[ -n "$session_name" && -n "$session_date" && -n "$session_n_measurements" ]]; then
                echo "$session_name, $session_date, $session_n_measurements"
                break
            fi
        done < "$info_file"

    fi

}


SESSION_DIR_CONTENTS=$(find "$SESSION_DIR" -mindepth 1 -maxdepth 1 -type d  ! -path "$SESSION_DIR")

SESH_LIST=""
N_SESSIONS_FOUND=0

while IFS= read -r session; do
    if [ -d "$session" ]; then
        session_info=$(process_session "$session")
        if [ -n "$session_info" ]; then
            SESH_LIST+="$session_info"
            SESH_LIST+=$'\n' # Add a newline after each session info
            ((N_SESSIONS_FOUND++))
        fi
    fi
done <<< "$SESSION_DIR_CONTENTS"


if [ -z "$NUM_SESSIONS"  ]; then
    NUM_SESSIONS=$N_SESSIONS_FOUND
fi

OLDEST_TO_NEWEST=$(echo -e -n "$SESH_LIST" | sort -t ',' -k2,2 -k1,1)


if [ -n "$OLD_SESSIONS" ]; then
    SHORT_SESH_LIST=$(echo -e -n "$OLDEST_TO_NEWEST" | head -n "$NUM_SESSIONS")
else
    SHORT_SESH_LIST=$(echo -e -n "$OLDEST_TO_NEWEST" | tail -n "$NUM_SESSIONS")
fi

if [ -n "$COUNT_SESSIONS" ]; then
    if [ $NUM_SESSIONS -lt $N_SESSIONS_FOUND ]; then
        echo "$NUM_SESSIONS"
    else
        echo "$N_SESSIONS_FOUND"
    fi
    exit 0
fi


if [ -n "$REVERSE_ORDER" ]; then
    FINAL_SESH_LIST=$(echo -e "$SHORT_SESH_LIST" | tac)
else
    FINAL_SESH_LIST="$SHORT_SESH_LIST"
fi

if [ -n "$SESSION_NAMES_ONLY" ]; then
    FINAL_SESH_LIST=$(echo -e "$FINAL_SESH_LIST" | cut -d',' -f1 | tr '\n' "$DELIMITER")
    FINAL_SESH_LIST=${FINAL_SESH_LIST%$DELIMITER} # Remove trailing delimiter
fi


echo -e "$FINAL_SESH_LIST"


