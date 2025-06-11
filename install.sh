#!/bin/bash

TOOL_NAME="AEGIR"

TOOL_LOWER="$(echo "$TOOL_NAME" | tr '[:upper:]' '[:lower:]')"
CONDA_ENV_NAME="${TOOL_LOWER}"

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Exiting..."
    exit 1
fi

echo "Installing $TOOL_NAME..."

GROUP_NAME="${TOOL_LOWER}-group"

echo "Creating group $GROUP_NAME..."

groupadd -f "$GROUP_NAME"
usermod -aG "$GROUP_NAME" "$SUDO_USER"


USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

MINIFORGE_DIR="${USER_HOME}/miniforge3"

ENV_DIR="$MINIFORGE_DIR/envs/${CONDA_ENV_NAME}"


# Check if conda environment exists
if ! conda env list | grep -q -w "$CONDA_ENV_NAME"; then
    echo "Conda environment '$CONDA_ENV_NAME' does not exist."
    read -e -p "Create conda environment '$CONDA_ENV_NAME'? [Y/n]" CREATE_CONDA_ENV
    if [ "$CREATE_CONDA_ENV" == "" ]; then
        CREATE_CONDA_ENV="y"
    fi
    if [ "$CREATE_CONDA_ENV" == "y" ]; then
        echo "Creating conda environment '$CONDA_ENV_NAME'..."
        conda env create -f environment.yml
    else
        echo "Skipping conda environment creation. Aegir may not work properly without the conda environment."
    fi
    
fi


# Get script directory
BASE_DIR="$(dirname "$(readlink -f "$0")")"
PARENT_DIR="$(dirname "$dir")"
USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

AEGIR_SYMBOLIC_LINK="/usr/local/bin/aegir"
AGR_SYMBOLIC_LINK="/usr/local/bin/agr"



echo "Checking for .env file..."
ENV_FILE="$BASE_DIR/.env"


USE_EXISTING_ENV="y"

if [ -f "$ENV_FILE" ]; then
    echo ".env file found at $ENV_FILE"
    read -e -p "Do you want to use this .env file? [Y/n] " USE_EXISTING_ENV
    if [ "$USE_EXISTING_ENV" != "n" ] && [ "$USE_EXISTING_ENV" != "N" ]; then
        echo "Using existing .env file at $ENV_FILE"
        USE_EXISTING_ENV="y"

        # Load environment variables from .env file
        export $(grep -v '^#' "$ENV_FILE" | xargs)
    fi
else
    USE_EXISTING_ENV="n"
fi



if [ "$USE_EXISTING_ENV" == "n" ] || [ "$USE_EXISTING_ENV" == "N" ]; then
    echo ".env file not found at $ENV_FILE. Creating one..."
    touch "$ENV_FILE"


    DATA_DIR="$USER_HOME/${TOOL_NAME}_DATA"
    read -e -p "Use default location for captured data: $DATA_DIR? [Y/n]" ACCEPT_DEFAULT_DIR 
    if [ "$ACCEPT_DEFAULT_DIR" == "" ]; then
        ACCEPT_DEFAULT_DIR="y"
    fi

    ACCEPT_DEFAULT_DIR=$(echo "$ACCEPT_DEFAULT_DIR" | tr '[:upper:]' '[:lower:]')

    if [ "$ACCEPT_DEFAULT_DIR" == "n" ]; then
        
        read -e -p "Enter the path to the data directory: " DATA_DIR
        if [ ! -d "$DATA_DIR" ]; then
            PARENT_DIR=$(dirname "$DATA_DIR")
            if [ ! -d "$PARENT_DIR" ]; then
                echo "Invalid directory. Exiting..."
                exit 1
            
            fi
        else
        DATA_DIR="${DATA_DIR}/${TOOL_NAME}_DATA"
        fi
    elif [ ! "$ACCEPT_DEFAULT_DIR" == "y" ]; then
        echo "Invalid input: \"$ACCEPT_DEFAULT_DIR\". Exiting..."
        exit 1
    fi


    echo "Enter location of IDS Peak installation:"
    read -e -p "(e.g /opt/ids-peak-with-ueyetl_[version_num]_[architecture]):" IDS_PEAK_DIR

    if [ ! -d "$IDS_PEAK_DIR" ]; then
        echo "IDS Peak installation directory does not exist. Exiting..."
        exit 1
    fi




    echo "Creating data directory in $DATA_DIR..."
    mkdir -p "$DATA_DIR"
    mkdir -p "$DATA_DIR/routines"
    mkdir -p "$DATA_DIR/sessions"
    mkdir -p "$DATA_DIR/logs"
    mkdir -p "$DATA_DIR/config"


    echo "Copying example routines to $DATA_DIR/routines..."
    cp -a "$BASE_DIR/example_routines/." "$DATA_DIR/routines/"

    # Change ownership of data directory to user
    chown -R $SUDO_USER: "$DATA_DIR"



USB_BUFFER_SIZE_FILE="/sys/module/usbcore/parameters/usbfs_memory_mb"
USB_BUFFER_SIZE=$(cat "$USB_BUFFER_SIZE_FILE" 2>/dev/null)
if [ -z "$USB_BUFFER_SIZE" ]; then
    echo "USB buffer size file not found. Skipping USB buffer size adjustment."
else
    echo "Current USB buffer size: $USB_BUFFER_SIZE mb"
fi

if [ "$USB_BUFFER_SIZE" -lt 1000 ]; then
    echo "Increasing USB buffer size to 1000mb..."
    echo 1000 > "$USB_BUFFER_SIZE_FILE"
else
    echo "USB buffer size is already set to $USB_BUFFER_SIZE mb or higher."
fi


    echo "Creating .env file at $ENV_FILE..."

    echo "Edit this file to change the data directory or IDS Peak installation directory, and to adjust location of named pipes."

    echo "IDS_PEAK_DIR=\"$IDS_PEAK_DIR\"" >> "$ENV_FILE"
    echo "DATA_DIRECTORY=\"$DATA_DIR\"" > "$ENV_FILE"
    echo "PIPE_IN_FILE=\"/tmp/${TOOL_NAME}_IN\"" >> "$ENV_FILE"
    echo "PIPE_OUT_FILE=\"/tmp/${TOOL_NAME}_OUT\"" >> "$ENV_FILE"
    echo "PYTHON_EXECUTABLE=\"${PYTHON_EXE}\"" >> "$ENV_FILE"
    chown -R $SUDO_USER: "$ENV_FILE"

fi



CONFIG_DIR="/etc/${TOOL_LOWER}"
CONFIG_FILE="${CONFIG_DIR}/${TOOL_LOWER}.conf"

USE_EXISTING_CONFIG="y"
if [ -f "$CONFIG_FILE" ]; then
    echo "Configuration file $CONFIG_FILE already exists."
    read -e -p "Do you want to use it? [Y/n] " OVERWRITE_CONFIG
    if [ "$OVERWRITE_CONFIG" == "y" ] || [ "$OVERWRITE_CONFIG" == "Y" ] || [ "$OVERWRITE_CONFIG" == "" ]; then
        echo "Keeping existing configuration file."
        USE_EXISTING_CONFIG="y"
    else
        echo "Overwriting existing configuration file..."
        USE_EXISTING_CONFIG="n"
    fi

else
    echo "Configuration file $CONFIG_FILE does not exist. Creating one..."
    USE_EXISTING_CONFIG="n"
fi


if [ "$USE_EXISTING_CONFIG" == "n" ]; then
    echo "Creating configuration file at $CONFIG_FILE..."

    echo "Creating config directory in /etc/${TOOL_LOWER}..."

    mkdir -p "$CONFIG_DIR"
    chown -R $SUDO_USER:$GROUP_NAME "$CONFIG_DIR"

    echo "ENV_FILE=\"$ENV_FILE\"" > "$CONFIG_FILE"
    echo "TERM_USER=\"$SUDO_USER\"" >> "$CONFIG_FILE"

    chown -R $SUDO_USER:$GROUP_NAME "$CONFIG_FILE"
    chmod 774 "$CONFIG_FILE"

    echo "$CONFIG_FILE created. This has the ENV_FILE variable set to the location of the .env file, which contains the data directory and other environment variables."
    echo "and the TERM_USER variable set to the user that ran this script, which is used to set the autologin"
fi

EXECUTABLE_DIR="/usr/local/bin"
TOOL_TARGET="$EXECUTABLE_DIR/${TOOL_LOWER}"
SESSION_HANDLER_TARGET="$EXECUTABLE_DIR/${TOOL_LOWER}Sesh"
SESSION_ZIP_TARGET="$EXECUTABLE_DIR/${TOOL_LOWER}Zip"



echo "Installing ${TOOL_NAME}, ${TOOL_LOWER}Sesh, and ${TOOL_LOWER}Zip in $EXECUTABLE_DIR..."

SCRIPTS_DIR="${BASE_DIR}/scripts"

install -D -o "$SUDO_USER" -m 774 -g "$GROUP_NAME" "$SCRIPTS_DIR/run.sh" "$TOOL_TARGET"
install -D -o "$SUDO_USER" -m 774 -g "$GROUP_NAME" "$SCRIPTS_DIR/sesh.sh" "$SESSION_HANDLER_TARGET"
install -D -o "$SUDO_USER" -m 774 -g "$GROUP_NAME" "$SCRIPTS_DIR/zip.sh" "$SESSION_ZIP_TARGET"


echo "Setting up systemd service for ${TOOL_NAME}..."


# Service files in install directory
# These will be copied to /etc/systemd/system
BASE_SERVICE_DIR="${BASE_DIR}/services"

LOGGING_SERVICE_FILE="${BASE_SERVICE_DIR}/logging@.service"
TERMINAL_SERVICE_FILE="${BASE_SERVICE_DIR}/serialTerm@.service"
AUTOSTART_SERVICE_FILE="${BASE_SERVICE_DIR}/autostart@.service"
SERVER_SERVICE_FILE="${BASE_SERVICE_DIR}/dataserver@.service"

LOGGER_SCRIPT="${SCRIPTS_DIR}/log.sh"

# Target directories for service files

SYSTEMD_SERVICE_DIR="/etc/systemd/system"

LOGGING_SERVICE_FILE_TARGET="${SYSTEMD_SERVICE_DIR}/logging@${TOOL_LOWER}.service"

TERMINAL_SERVICE_FILE_TARGET="${SYSTEMD_SERVICE_DIR}/serialTerm@${TOOL_LOWER}.service"
TERMINAL_SERVICE_CONFIG_DIR="${TERMINAL_SERVICE_FILE_TARGET}.d"

AUTOSTART_SERVICE_FILE_TARGET="${SYSTEMD_SERVICE_DIR}/autostart@${TOOL_LOWER}.service"
AUTOSTART_SERVICE_CONFIG_DIR="${AUTOSTART_SERVICE_FILE_TARGET}.d"

SERVER_SERVICE_FILE_TARGET="${SYSTEMD_SERVICE_DIR}/dataserver@${TOOL_LOWER}.service"
SERVER_SERVICE_CONFIG_DIR="${SERVER_SERVICE_FILE_TARGET}.d"

## Service for logging to dh4 and running the serial terminal

install -g "$GROUP_NAME" -m 644 "$LOGGING_SERVICE_FILE" "$LOGGING_SERVICE_FILE_TARGET"

install -D -g "$GROUP_NAME" -m 774 "$LOGGER_SCRIPT" "$EXECUTABLE_DIR/${TOOL_LOWER}Log"

systemctl enable "logging@${TOOL_LOWER}.service"


install -g "$GROUP_NAME" -m 644 "$TERMINAL_SERVICE_FILE" "$TERMINAL_SERVICE_FILE_TARGET"
mkdir -p "$TERMINAL_SERVICE_CONFIG_DIR"

# Create the variables.conf file for the terminal service
# This file will contain the TERM_USER variable, which is used to set the user for the serial terminal
echo "[Service]" > "$TERMINAL_SERVICE_CONFIG_DIR/variables.conf"
echo "Environment=\"TERM_USER=\\\"$SUDO_USER\\\"\"" >> "$TERMINAL_SERVICE_CONFIG_DIR/variables.conf"

# Autostart service for running the program on boot

install -g "$GROUP_NAME" -m 644 "$AUTOSTART_SERVICE_FILE" "$AUTOSTART_SERVICE_FILE_TARGET"

mkdir -p "$AUTOSTART_SERVICE_CONFIG_DIR"
echo "[Service]" > "$AUTOSTART_SERVICE_CONFIG_DIR/variables.conf"
echo "Group=$GROUP_NAME" >> "$AUTOSTART_SERVICE_CONFIG_DIR/variables.conf"

systemctl enable "autostart@${TOOL_LOWER}.service"

# Service for running the dataserver - disabled in AEGIR for now


# # Copy the server files to /etc/${TOOL_LOWER}/server (html, css, js, etc.)
# mkdir -p "/etc/${TOOL_LOWER}/server"
# cp -r "${BASE_DIR}/server/"* "/etc/${TOOL_LOWER}/server/"
# chmod -R 644 "/etc/${TOOL_LOWER}/server"


# install -g "$GROUP_NAME" -m 644 "$SERVER_SERVICE_FILE" "$SERVER_SERVICE_FILE_TARGET"
# mkdir -p "$SERVER_SERVICE_CONFIG_DIR"
# echo "[Service]" > "$SERVER_SERVICE_CONFIG_DIR/variables.conf"
# echo "Group=$GROUP_NAME" >> "$SERVER_SERVICE_CONFIG_DIR/variables.conf"

# systemctl enable "dataserver@${TOOL_LOWER}.service"


UDEV_RULES_FILE="/etc/udev/rules.d/99-${TOOL_LOWER}.rules"
echo "Creating udev rules file at $UDEV_RULES_FILE..."
echo "This will trigger the logger service to start when the device is connected."
echo "You may need to modify the ATTRS{idProduct} and ATTRS{idVendor} values to match your device."
echo "By default it will match the FT232R USB UART device."
echo "Use udevadm info -a -n /dev/ttyUSB[x] to find the correct values for your device."

echo "SUBSYSTEM==\"tty\", ATTRS{idProduct}==\"6001\", ATTRS{idVendor}==\"0403\", ATTRS{product}==\"FT232R USB UART\", SYMLINK+=\"DH4\", MODE:=\"0774\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}+=\"logger@${TOOL_LOWER}.service\"" > "$UDEV_RULES_FILE"

# Build bar30 c program
echo "Compiling bar30 program..."

cd "$BASE_DIR/bar30"
echo "Building bar30..."
make clean
make

if [ $? -ne 0 ]; then
    echo "Error: Failed to build bar30 program. Exiting..."
    exit 1
else
    echo "bar30 program built successfully."
fi

cd -

install -g "$GROUP_NAME" -m 774 -D "$BASE_DIR/bar30/build/depthLogger" "$EXECUTABLE_DIR/depthLogger"


# Add lines in .bashrc to set TMOUT for serial terminal
# This will set the TMOUT variable to 60 seconds when the user is logged in via the serial terminal
# and the device is connected to /dev/DH4 or /dev/ttyUSB0

BASHRC_FILE="/home/$SUDO_USER/.bashrc"
echo "Checking for ${TOOL_NAME} in $BASHRC_FILE..."



grep -qxF "#${TOOL_NAME}_TMOUT_SERIAL" "$BASHRC_FILE"

if [ $? -ne 0 ]; then
    echo "Adding ${TOOL_NAME} setup to $BASHRC_FILE..."
    echo "#${TOOL_NAME}_TMOUT_SERIAL" >> "$BASHRC_FILE"
    echo "DH4_DEVICE_PATH=\$(readlink -f \"/dev/DH4\")" >> "$BASHRC_FILE"
    echo "TTY=\$(tty)" >> "$BASHRC_FILE"
    echo "if [[ \"\$TTY\" == *\"\$DH4_DEVICE_PATH\"* || \"\$TTY\" == *\"/dev/DH4\"* ]]; then" >> "$BASHRC_FILE"
    echo "  export TMOUT=60" >> "$BASHRC_FILE"
    echo "fi" >> "$BASHRC_FILE"
else
    echo "${TOOL_NAME} setup already exists in $BASHRC_FILE. Skipping..."
fi

echo "Installation complete. Reboot your system to apply changes."
