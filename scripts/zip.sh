#!/bin/bash


TOOL_NAME="AEGIR"
TOOL_LOWER=$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')



# This script takes arguments which are the names of sessions in the session directory.

###################################################################
######################## Process Arguments ########################
###################################################################

show_help() {
    echo "${TOOL_LOWER}Zip.sh - Zip ${TOOL_NAME} sessions"
    echo ""
    echo "This script zips the specified ${TOOL_NAME} sessions into a single .tar.gz file."
    echo ""
    echo "Usage: $0 [-h] [-t] [-l] [-v] [-x] [-d] [-z]|[-Z ARGS] [session_name ...]"
    echo ""
    echo "Options:"
    echo "  -h               Display this help message"
    echo "  -t               Just add the sessions to the tar file without compressing it with gzip."
    echo "                      (i.e. create a .tar file instead of a .tar.gz file)"
    echo "  -l               List the names of the sessions that will be zipped."
    echo "  -v               Enable verbose output."
    echo "  -x               Exclude session logs from the zip file. (Can save considerable space)"
    echo "  -d               Dry run mode. Will output the tar command that would be run, but not execute it."
    echo "  -z               Use lrzsz to send the output file using ZMODEM protocol."
    echo "                      (Requires lrzsz to be installed and configured on the system, and the"
    echo "                      user to be logged in to a terminal that supports ZMODEM (e.g Tera Term, minicom, etc.).)"
    echo "  -Z ARGS          Same as -z, but the provided ARGS will be passed to the sz command."
    echo "                      Args should be surrounded by quotes if they contain spaces."
    echo "                      Use caution - if this is the last argument and you do not provide a value,"
    echo "                      the script will likely use the first session name as the argument to sz."
    echo "Arguments:"
    echo "  session_name     The name of the session to zip. If no session names are provided, all"
    echo "                      sessions in the session directory will be zipped. Any invalid"
    echo "                      session names will be ignored."
    
    exit 0
}

echoverb () {
    if [[ $VERBOSE == true ]]; then
        echo "$@"
    fi
}

TAR_ONLY=false
LIST_NAMES=false
VERBOSE=false
EXCLUDE_LOGS=false
DRY_RUN=false

while getopts ":htlvxdzZ:" opt; do
    case $opt in
        h)
            show_help
            ;;
        t)
            TAR_ONLY=true
            ;;
        l)
            LIST_NAMES=true
            ;;
        v)
            VERBOSE=true
            ;;
        x)
            EXCLUDE_LOGS=true
            ;;
        d)
            DRY_RUN=true
            ;;
        z)
            ZMODEM=true
            ;;
        Z)
            ZMODEM=true
            if [[ -n "$OPTARG" ]]; then
                ZMODEM_ARGS="$OPTARG"
            else
                ZMODEM_ARGS=""
            fi
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            exit 1
            ;;
    esac
done

if [[ "$ZMODEM" == true ]]; then
    if ! command -v sz &> /dev/null; then
        echoverb "Error: lrzsz is not installed. Please install it to use ZMODEM functionality." >&2
        exit 1
    fi
fi

################################################################################
########################## Load Environment Variables ##########################
################################################################################


CONFIG_FILE="/etc/${TOOL_LOWER}/${TOOL_LOWER}.conf"

if [ -f "$CONFIG_FILE" ]
then
    # CONF file contains ENV_FILE variable, load it
    source "$CONFIG_FILE"
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
    echoverb "Error: DATA_DIRECTORY is not set in $ENV_FILE"
    exit 1
fi

SESSION_DIR="$DATA_DIRECTORY/sessions"

# Check if the data directory exists
if [ ! -d "$SESSION_DIR" ]; then
    echoverb "Error: Session directory $SESSION_DIR does not exist."
    exit 1
fi


is_valid_session_name() {
    local session_name="$1"
    [[ -d "$SESSION_DIR/$session_name" ]]
}


shift $((OPTIND - 1))

NAME_LIST=($@)

if [[ ${#NAME_LIST[@]} -eq 0 ]]; then
    echoverb "No session names provided. Zipping all sessions in $SESSION_DIR."
    
    # Get all session directories in the session directory, checking if they are valid session names
    while IFS= read -r -d '' session; do
        session_name=$(basename "$session")
        NAME_LIST+=("$session_name")
    done < <(find "$SESSION_DIR" -mindepth 1 -maxdepth 1 -type d ! -path "$SESSION_DIR" -print0)
else
    if [[ ${#NAME_LIST[@]} -gt 1 ]]; then
        PLURAL="s"
    fi
    echoverb "${#NAME_LIST[@]} session name${PLURAL} provided."
fi

if [[ ${#NAME_LIST[@]} -eq 0 ]]; then
    echoverb "No valid session names found in $SESSION_DIR."
    exit 0
fi

((INVALID=0))

for name in "${NAME_LIST[@]}"
do
    if ! is_valid_session_name "$name"; then
        ((INVALID++))
        continue
    fi
    if [[ -n "$SESSION_NAMES" ]]; then
        SESSION_NAMES+=$'\n'  # Add a newline for separation
    fi
    SESSION_NAMES+=("$name")
    
done


#Get unique session names
SESSION_NAMES=($(echo "${SESSION_NAMES[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

N_VALID_SESSIONS="${#SESSION_NAMES[@]}"

if [[ $INVALID -gt 0 ]]; then
    echoverb "Skipping $INVALID invalid session name(s)."
fi

if [[ $N_VALID_SESSIONS -eq 0 ]]; then
    echoverb "No valid sessions found to zip." >&2
    exit 1
fi

if [[ $N_VALID_SESSIONS -gt 1 ]]; then
        PLURAL="s"
fi
echoverb "$N_VALID_SESSIONS valid session$PLURAL from '$SESSION_DIR'"


if [[ "$LIST_NAMES" == true ]]; then
    echo "Session$PLURAL to be zipped:"
    for name in "${SESSION_NAMES[@]}"; do
        echo "- $name"
    done

fi

ZIP_DIR="$DATA_DIRECTORY/zipped_sessions"




tar_file="$ZIP_DIR/${TOOL_LOWER}_sessions_$(date +%Y-%m-%d_%H-%M-%S).tar"
if [[ $TAR_ONLY == true ]]; then
    tar_file="$tar_file"
else
    tar_file="$tar_file.gz"
fi

tar_cmd="tar -cf $tar_file"
if [[ $TAR_ONLY == false ]]; then
    tar_cmd+=" -z"
fi

if [[ $EXCLUDE_LOGS == true ]]; then
    tar_cmd+=" --exclude='*.log'"
fi


for name in "${SESSION_NAMES[@]}"; do
    if [[ "$EXCLUDE_LOGS" == true && "$VERBOSE" == true ]]; then
        THIS_UNCOMPRESSED_SIZE=$(($(du -s --exclude='*.log' "$SESSION_DIR/$name" | cut -f1)))
        THIS_SAVED_SIZE=$(($(du -s "$SESSION_DIR/$name" | cut -f1) - $(du -s --exclude='*.log' "$SESSION_DIR/$name" | cut -f1)))
        
        UNCOMPRESSED_SIZE=$((UNCOMPRESSED_SIZE + THIS_UNCOMPRESSED_SIZE))
        SAVED_SIZE=$((SAVED_SIZE + THIS_SAVED_SIZE))
    elif [[ "$VERBOSE" == true ]]; then
        THIS_UNCOMPRESSED_SIZE=$((UNCOMPRESSED_SIZE + $(du -s "$SESSION_DIR/$name" | cut -f1)))
        UNCOMPRESSED_SIZE=$((UNCOMPRESSED_SIZE + THIS_UNCOMPRESSED_SIZE))
    fi
    tar_cmd+=" -C \"$SESSION_DIR\" \"$name\""
done

if [[ "$VERBOSE" == true ]]; then
    
    UNIT=""
    # Convert kb to mb if size is greater than 1024

    if [[ $UNCOMPRESSED_SIZE -lt 1024 ]]; then
        UNIT="KiB"
    elif [[ $UNCOMPRESSED_SIZE -lt 1048576 ]]; then
        UNIT="MiB"
        UNCOMPRESSED_SIZE=$(awk "BEGIN {printf \"%.2f\", $UNCOMPRESSED_SIZE / 1024}")
        if [[ -n "$SAVED_SIZE" && $SAVED_SIZE -gt 0 ]]; then
            SAVED_SIZE=$(awk "BEGIN {printf \"%.2f\", $SAVED_SIZE / 1024}")
        fi
    else
        UNIT="GiB"
        UNCOMPRESSED_SIZE=$(awk "BEGIN {printf \"%.2f\", $UNCOMPRESSED_SIZE / 1048576}")
        if [[ -n "$SAVED_SIZE" && $SAVED_SIZE -gt 0 ]]; then
            SAVED_SIZE=$(awk "BEGIN {printf \"%.2f\", $SAVED_SIZE / 1048576}")
        fi
    fi

fi

if [[ $DRY_RUN == true ]]; then
    echoverb "Dry run mode enabled. The following command would be executed:"
    echo "$tar_cmd"

    echoverb "Total uncompressed size of selected sessions: $UNCOMPRESSED_SIZE $UNIT"
    if [[ "$EXCLUDE_LOGS" == true ]]; then
        echoverb "Session logs will be excluded from the tar file."
        if [[ -n "$SAVED_SIZE" ]]; then
            echoverb "Estimated space saved by excluding logs:$SAVED_SIZE $UNIT"
        fi
        
    else
        echoverb "Session logs will be included in the tar file."
    fi
    echoverb "Tar file would be created at: $tar_file"
    exit 0
fi


echoverb "Running command: $tar_cmd"


mkdir -p "$ZIP_DIR" || {
    echoverb "Error: Failed to create zipped_sessions directory in $DATA_DIRECTORY." >&2
    exit 1
}

if ! eval "$tar_cmd"; then
    echoverb "Error: Failed to create tar file." >&2
    exit 1
fi

echoverb "Tar file created successfully:"
echo "$tar_file"





COMPRESSED_SIZE=$(du -s "$tar_file" | cut -f1)

case $UNIT in
    MiB)
        COMPRESSED_SIZE=$(awk "BEGIN {printf \"%.2f\", $COMPRESSED_SIZE / 1024}")
        ;;
    GiB)
        COMPRESSED_SIZE=$(awk "BEGIN {printf \"%.2f\", $COMPRESSED_SIZE / 1048576}")
        ;;
esac

echoverb "Uncompressed size: $UNCOMPRESSED_SIZE $UNIT"
echoverb "Compressed size: $COMPRESSED_SIZE $UNIT"
echoverb "Compression ratio: $(awk "BEGIN {printf \"%.2f\", $UNCOMPRESSED_SIZE / $COMPRESSED_SIZE}")"

if [[ "$ZMODEM" == true ]]; then
    if ! command -v sz &> /dev/null; then
        echoverb "Error: lrzsz is not installed. Please install it to use ZMODEM functionality." >&2
        exit 1
    fi

    echoverb "Sending tar file using ZMODEM protocol..."
    if ! sz "$ZMODEM_ARGS" "$tar_file"; then
        echoverb "Error: Failed to send tar file using ZMODEM." >&2
        exit 1
    fi
    echoverb "Tar file sent successfully using ZMODEM."
fi

