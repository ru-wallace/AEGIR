#!/bin/bash

echo "Building AEGIR..."

source activate base
CONDA_ENV_NAME="aegir"

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

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
        read -p "Enter name of conda environment to use or leave blank for base: " CONDA_ENV_NAME
        if [ "$CONDA_ENV_NAME" == "" ]; then
            CONDA_ENV_NAME="base"
        fi
        if ! conda env list | grep -q -w "$CONDA_ENV_NAME"; then
            echo "Conda environment '$CONDA_ENV_NAME' does not exist. Exiting..."
            exit 1
        fi
       
       
    fi
fi

conda activate "$CONDA_ENV_NAME"
if [ $? -ne 0 ]; then
    echo "Error activating conda environment. Exiting..."
    exit 1
fi      
# Check for missing dependencies
CONDA_SECTION=0
PIP_SECTION=0

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'
SOURCE=""
ALL_PRESENT=1
echo "Checking for missing dependencies in environment $CONDA_ENV_NAME..."

while IFS= read -r LINE; do
    #Strip leading characters
    LINE="$(echo "$LINE" | sed -e 's/^[ \t-]*//')"
    if [ "$LINE" == "dependencies:" ]; then
        SOURCE="conda"
        echo "Conda dependencies:"
        continue
    elif [ "$LINE" == "pip:" ]; then
        SOURCE="pip"
        echo "Pip dependencies:"
        continue
    fi
    if [ "$SOURCE" == "" ]; then
        continue
    fi

    DEPENDENCY=$(echo $LINE | cut -d'=' -f1)


    if [ "$SOURCE" == "conda" ]; then
        VERSION=$(echo $LINE | cut -d'=' -f2)
    else
        VERSION=$(echo "$LINE" | cut -d'=' -f3)
    fi
    MISSING_STRING=""
    COLOUR=$GREEN
    if ! conda list | grep -q -w "$DEPENDENCY"; then
        COLOUR=$RED
        MISSING_STRING=" (missing)"
        ALL_PRESENT=0
    fi

    printf "${COLOUR} %-20s ${NC} %s %s\n" "$DEPENDENCY" "$VERSION" "$MISSING_STRING"

    
done < environment.yml

if [ $ALL_PRESENT -eq 1 ]; then
    echo "All dependencies are present."
else
    echo "Missing dependencies found. Please install missing dependencies."
    exit 1
fi
# Print missing dependencies

cd "$SCRIPT_DIR/python_scripts" > /dev/null
pyinstaller --onefile aegir.py
if [ $? -ne 0 ]; then
    echo "Error creating executable. Exiting..."
    cd - > /dev/null
    exit 1
fi
cd - > /dev/null

if [ -d "$SCRIPT_DIR/build" ]; then
    rm -r "$SCRIPT_DIR/build"
fi

mkdir "$SCRIPT_DIR/build"
cp "$SCRIPT_DIR/python_scripts/dist/aegir" "$SCRIPT_DIR/build/aegir"
cp "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/build/install.sh"
cp "$SCRIPT_DIR/aegir.sh" "$SCRIPT_DIR/build/aegir.sh"
cp "$SCRIPT_DIR/example_routines" "$SCRIPT_DIR/build/example_routines" -r

#Compress to tar.gz
tar -czvf "$SCRIPT_DIR/build.tar.gz" "$SCRIPT_DIR/build"
if [ $? -ne 0 ]; then
    echo "Error compressing build directory. Exiting..."
    rm -r "$SCRIPT_DIR/build"
    exit 1
fi

rm -r "$SCRIPT_DIR/build"

