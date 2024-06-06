#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/devcontainer-feature-k3s/README.md

K3S_VERSION="${K3SVERSION:-"latest"}"
USE_CRI_DOCKERD="${CRIDOCKERD:-"true"}"
HOST_INTERFACE_CONTAINER="host_interface"
HOST_INTERFACE_CONTAINER_BASE="mcr.microsoft.com/devcontainers/base:ubuntu22.04"

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi


# Source /etc/os-release to get OS info
. /etc/os-release
# Fetch host/container arch.
ARCHITECTURE="$(dpkg --print-architecture)"
K3S_ARCHITECTURE=$ARCHITECTURE


############################################################
# Build the spacefx-dev directory and copy any files that'll be used while running the container
############################################################
function build_dest_directory() {

    echo "Creating /spacefx-dev directory..."
    mkdir -p "/spacefx-dev"

    mkdir -p "/host_var/tmp/spacefx-dev"

    echo "Creating /spacefx-dev/.env file..."
    tee /spacefx-dev/.env -a > /dev/null << UPDATE_END
export _REMOTE_USER=${_REMOTE_USER}
export _REMOTE_USER_HOME=${_REMOTE_USER_HOME}
export _CONTAINER_USER=${_CONTAINER_USER}
export K3S_VERSION=${K3S_VERSION}
export KUBECTL_VERSION=${KUBECTL_VERSION}
export USE_CRI_DOCKERD=${USE_CRI_DOCKERD}
export ARCHITECTURE=${ARCHITECTURE}
export HOST_INTERFACE_CONTAINER=${HOST_INTERFACE_CONTAINER}
export K3S_ARCHITECTURE=${K3S_ARCHITECTURE}
export HOST_INTERFACE_CONTAINER_BASE=${HOST_INTERFACE_CONTAINER_BASE}
UPDATE_END


    echo "Copying scripts to /spacefx-dev/..."
    cp ./*.sh /spacefx-dev/
    cp ./azure-orbital-space-sdk-setup /azure-orbital-space-sdk-setup/ -r


    while read -r shellFile; do
        chmod +x ${shellFile}
        chmod 777 ${shellFile}
    done < <(find "/spacefx-dev" -iname "*.sh")

}

function main() {
    build_dest_directory
}


main
set +e