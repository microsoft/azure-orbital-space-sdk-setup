#!/bin/bash
#
# Downloads the python packages specified in pypiserver/requirements.txt via pip
# and uploads them to coresvc-registry's pypi server via twine.
#
# Example Usage:
#
# bash ./pypiserver/scripts/stage_python_packages.sh

############################################################
# Script variables
############################################################

# The directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# The directory where the python packages will be downloaded to
PACKAGE_STAGING_DIR="/data/staging"

# The endpoint of the coresvc-registry's pypi server
SPACEFX_PYPI_SERVER="https://localhost:8080"

############################################################
# Help
############################################################

function show_help() {
    echo "Usage: $0"
    echo ""
    echo "Downloads the python packages specified in pypiserver/requirements.txt via pip"
    echo "and uploads them to coresvc-registry's pypi server via twine."
    echo ""
    echo "Example Usage:"
    echo ""
    echo "bash ./pypiserver/scripts/stage_python_packages.sh"
    echo ""
    exit 1
}

############################################################
# Main
############################################################

# Check if requirements.txt exists
if [ ! -f "${SCRIPT_DIR}/../requirements.txt" ]; then
    echo "ERROR: pypiserver/requirements.txt does not exist."
    show_help
elif [ ! -s "${SCRIPT_DIR}/../requirements.txt" ]; then
    echo "WARNING: pypiserver/requirements.txt is empty. Skipping staging."
    exit 0
fi

# Empty and recreate the package staging directory
rm -rf "${PACKAGE_STAGING_DIR}"
mkdir -p "${PACKAGE_STAGING_DIR}"

# Install the python packages specified in requirements.txt
echo "Downloading python packages to ${PACKAGE_STAGING_DIR}"
pip download -r "${SCRIPT_DIR}/../requirements.txt" -d "${PACKAGE_STAGING_DIR}"

# Upload the python packages to coresvc-registry's pypi server
for package in $(ls ${PACKAGE_STAGING_DIR}); do
    echo "Uploading ${package} to ${SPACEFX_PYPI_SERVER}"
    /pypi-server/bin/twine upload --repository-url "${SPACEFX_PYPI_SERVER}" --username anonymous --password none "${PACKAGE_STAGING_DIR}/${package}"
done

# Clean up the package staging directory
rm -rf "${PACKAGE_STAGING_DIR}"
