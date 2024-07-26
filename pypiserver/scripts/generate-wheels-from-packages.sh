#!/bin/bash

# Get the directory of the script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Variables
PACKAGES_DIR="/usr/local/lib/python3.8/dist-packages"
WHEEL_OUTPUT_DIR="/workspace/dist"

# Reconstitutes a python wheel from a package in site-packages/dist-packages
generate_wheels() {
    PACKAGE_NAME=$1
    PACKAGE_VERSION=$2

    TEMP_DIR="${PACKAGE_NAME}_package"
    echo "Creating temporary directory: $TEMP_DIR"
    mkdir -p $TEMP_DIR

    # Find the package's RECORD file
    RECORD_FILE="${PACKAGES_DIR}/${PACKAGE_NAME}-${PACKAGE_VERSION}.dist-info/RECORD"
    if [ ! -f "$RECORD_FILE" ]; then
        echo "RECORD file not found for $PACKAGE_NAME"
        return
    fi

    # Create symlinks to package contents stated in RECORD_FILE to the temporary directory
    # skip paths starting with ../ or containing __pycache__ from the RECORD file
    echo "Creating symlinks for package contents in $TEMP_DIR"
    while IFS= read -r line; do
        FILEPATH=$(echo $line | cut -d ',' -f 1)
        DIRNAME=$(dirname $FILEPATH)
        FILE=$(basename $FILEPATH)
        if [[ $DIRNAME == ../* ]] || [[ $DIRNAME == *'__pycache__'* ]]; then
            continue
        fi
        TEMP_DIRNAME=$(echo $DIRNAME | sed 's#^\(\.\./\)*##')
        mkdir -p $TEMP_DIR/$TEMP_DIRNAME 2>/dev/null
        ln -s $PACKAGES_DIR/$DIRNAME/$FILE $TEMP_DIR/$TEMP_DIRNAME/$FILE
    done < $RECORD_FILE

    # Read the RECORD file in the temporary directory
    # remove paths starting with ../ or containing __pycache__ from the RECORD file
    RECORD_FILE="$TEMP_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.dist-info/RECORD"
    while IFS= read -r line; do
        FILEPATH=$(echo $line | cut -d ',' -f 1)
        DIRNAME=$(dirname $FILEPATH)
        FILE=$(basename $FILEPATH)
        if [[ $DIRNAME == ../* ]] || [[ $DIRNAME == *'__pycache__'* ]]; then
            sed -i "/$FILE/d" $RECORD_FILE
        fi
    done < $RECORD_FILE

    # Read tags from the WHEEL file
    WHEEL_FILE_PATH="$TEMP_DIR/${PACKAGE_NAME}-${PACKAGE_VERSION}.dist-info/WHEEL"
    TAGS=$(grep '^Tag:' $WHEEL_FILE_PATH | cut -d ' ' -f 2)

    # For each tag, determine if it's a multi-platform tag and generate a separate tag for each platform
    for TAG in $TAGS; do
        PYTHON_TAG=$(echo $TAG | cut -d '-' -f 1)
        ABI_TAG=$(echo $TAG | cut -d '-' -f 2)
        PLATFORM_TAG=$(echo $TAG | cut -d '-' -f 3)

        # Split the platform tag into multiple tags if it contains multiple platforms
        IFS='.' read -r -a PLATFORM_TAGS <<< "$PLATFORM_TAG"

        # If the platform tag contains multiple platforms, generate a separate tag for each platform
        if [ ${#PLATFORM_TAGS[@]} -gt 1 ]; then
            # Generate a separate tag for each platform
            for PLATFORM in ${PLATFORM_TAGS[@]}; do
                TAGS="$TAGS $PYTHON_TAG-$ABI_TAG-$PLATFORM"
            done

            # Remove the original tag
            TAGS=$(echo $TAGS | sed "s/$TAG//")
        fi
    done

    # Generate a wheel file for each tag
    for TAG in $TAGS; do
        echo "Generating wheel file for $PACKAGE_NAME with tag: $TAG"

        # Modify the WHEEL file to include only the current tag
        sed -i '/^Tag:/d' $WHEEL_FILE_PATH
        echo "Tag: $TAG" >> $WHEEL_FILE_PATH

        # Generate the wheel file
        python3 -m wheel pack $TEMP_DIR
        WHEEL_FILE=$(ls *.whl)
        mv $WHEEL_FILE $WHEEL_OUTPUT_DIR
    done

    # Remove the symlinked package contents
    echo "Removing symlinks for package contents in $TEMP_DIR"
    find $TEMP_DIR -type l -exec rm {} \;

    # Remove the temporary directory
    echo "Cleaning up temporary directory: $TEMP_DIR"
    cd $DIR
    rm -rf $TEMP_DIR
}

main() {
    # Get the list of packages in site-packages via ${PACKAGES_DIR}/*.dist-info
    echo "Iterating over packages in $PACKAGES_DIR"
    for dist_info in ${PACKAGES_DIR}/*.dist-info; do
        PACKAGE_NAME=$(basename $dist_info | sed 's/-[0-9].*//')
        PACKAGE_VERSION=$(basename $dist_info | sed 's/.*-\([0-9].*\)\.dist-info/\1/')
        echo "Found package: $PACKAGE_NAME, version: $PACKAGE_VERSION"
    done

    # Ensure the output directory exists
    echo "Creating output directory: $WHEEL_OUTPUT_DIR"
    mkdir -p $WHEEL_OUTPUT_DIR

    # Iterate over each package in site-packages
    for dist_info in ${PACKAGES_DIR}/*.dist-info; do
        PACKAGE_NAME=$(basename $dist_info | sed 's/-[0-9].*//')
        PACKAGE_VERSION=$(basename $dist_info | sed 's/.*-\([0-9].*\)\.dist-info/\1/')

        echo "Processing package: $PACKAGE_NAME, version: $PACKAGE_VERSION"
        generate_wheels $PACKAGE_NAME $PACKAGE_VERSION
    done
}

main