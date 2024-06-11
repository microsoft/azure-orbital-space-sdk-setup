#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md

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


function add_hosts_entry_for_coresvc_registry(){
    # Calculate the external ip of the host by checking the routes used to get to the internet
    debug_log "Calculating external ip..."
    run_a_script_on_host "ip route get 8.8.8.8" host_ip
    host_ip=${host_ip#*src }
    host_ip=${host_ip%% *}

    debug_log "...external ip: '${host_ip}'"

    debug_log "...retrieving coresvc-registry external url..."

    run_a_script "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" _registry_url

    _registry_url="${_registry_url%%:*}"

    debug_log "...adding hosts entry for '${_registry_url}' to '${host_ip}'..."

    run_a_script "tee -a /etc/hosts > /dev/null << SPACEFX_UPDATE_END
${host_ip}       ${_registry_url}
SPACEFX_UPDATE_END" --disable_log

}

function main() {
    initialize_spacedev_directory
    run_a_script_on_host "${SPACEFX_DIR}/scripts/stage_spacefx.sh"
    run_a_script_on_host "${SPACEFX_DIR}/scripts/deploy_spacefx.sh"
    add_hosts_entry_for_coresvc_registry
}

main