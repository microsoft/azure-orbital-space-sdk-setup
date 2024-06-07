#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/devcontainer-feature-k3s/README.md

export DEBIAN_FRONTEND=noninteractive

# Source /etc/os-release to get OS info
source /etc/os-release

source /spacefx-dev/.env

if [[ ! -d "${SPACEFX_DIR_FOR_HOST}" ]]; then
    mkdir -p ${SPACEFX_DIR_FOR_HOST}
fi

# Setup a symlink between the devcontainer SPACEFX_DIR to the host SPACEFX_DIR
# if one doesn't already exist
if [[ ! -L "${SPACEFX_DIR}" ]]; then
    ln -s ${SPACEFX_DIR_FOR_HOST} ${SPACEFX_DIR}
fi

# Copy all the files from the devcontainer to the host
cp /azure-orbital-space-sdk-setup/* ${SPACEFX_DIR_FOR_HOST} -r