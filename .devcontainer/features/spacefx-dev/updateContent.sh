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
source /spacefx-dev/utils.sh

############################################################
# Setup spacedev directory on host
############################################################
function initialize_spacedev_directory() {

    if [[ ! -d "${SPACEFX_DIR_FOR_HOST}" ]]; then
        run_a_script "mkdir -p ${SPACEFX_DIR_FOR_HOST}"
    fi

    # Setup a symlink between the devcontainer SPACEFX_DIR to the host SPACEFX_DIR
    # if one doesn't already exist
    if [[ ! -L "${SPACEFX_DIR}" ]]; then
        run_a_script "ln -s ${SPACEFX_DIR_FOR_HOST} ${SPACEFX_DIR}"
    fi

    # Copy all the files from the devcontainer to the host
    run_a_script "cp /azure-orbital-space-sdk-setup/* ${SPACEFX_DIR_FOR_HOST} -r"
}



function main() {
    initialize_spacedev_directory
    run_a_script_on_host "${SPACEFX_DIR}/scripts/stage_spacefx.sh"
    run_a_script_on_host "${SPACEFX_DIR}/scripts/deploy_spacefx.sh"
}


main