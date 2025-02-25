#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root. Exiting..."
    exit 1
fi

echo "Installing AEGIR..."


CONDA_ENV_NAME="aegir"

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
USER_HOME=$(getent passwd $SUDO_USER | cut -d: -f6)

AEGIR_SYMBOLIC_LINK="/usr/local/bin/aegir"
AGR_SYMBOLIC_LINK="/usr/local/bin/agr"

# Check if aegir symbolic link exists
if [ -L "$AEGIR_SYMBOLIC_LINK" ]; then
    rm "$AEGIR_SYMBOLIC_LINK"
fi

if [ -L "$AGR_SYMBOLIC_LINK" ]; then
    rm "$AGR_SYMBOLIC_LINK"
fi


echo "Checking for .env file..."
ENV_FILE="$BASE_DIR/.env"


# Exit if .env file exists
if [ -f "$ENV_FILE" ]; then
    echo ".env file already exists. Installation complete. Exiting..."
    exit 0
fi


# Create .env file and add text
DATA_DIR="$USER_HOME/AEGIR_DATA"
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
        DATA_DIR="$DATA_DIR/AEGIR_DATA"
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



echo "Copying example routines to $DATA_DIR/routines..."
cp -a "$BASE_DIR/example_routines/." "$DATA_DIR/routines/"

# Change ownership of data directory to user
chown -R $SUDO_USER: "$DATA_DIR"

echo "Increasing USB buffer size to 1000mb..."
echo 1000 > /sys/module/usbcore/parameters/usbfs_memory_mb

echo "Creating .env file at $ENV_FILE..."

echo "Edit this file to change the data directory or IDS Peak installation directory, and to adjust location of named pipes."

echo "DATA_DIRECTORY=\"$DATA_DIR\"" > "$ENV_FILE"
echo "IDS_PEAK_DIR=\"$IDS_PEAK_DIR\"" >> "$ENV_FILE"
echo "PIPE_IN_FILE=\"/tmp/AEGIR_IN\"" >> "$ENV_FILE"
echo "PIPE_OUT_FILE=\"/tmp/AEGIR_OUT\"" >> "$ENV_FILE"

chown -R $SUDO_USER: "$ENV_FILE"


echo "Creating symbolic link for aegir..."

ln -s "$BASE_DIR/aegir.sh" "$AEGIR_SYMBOLIC_LINK"
ln -s "$BASE_DIR/aegir.sh" "$AGR_SYMBOLIC_LINK"

chmod 777 "$BASE_DIR/aegir.sh"



echo "Installation complete. Exiting..."
