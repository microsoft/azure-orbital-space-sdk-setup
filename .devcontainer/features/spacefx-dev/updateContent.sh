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


############################################################
# Check if the certificate authority cert is in authorized certificate authorities for the host
############################################################
function add_ca_cert_to_trusted_root_authorities() {
    # shellcheck disable=SC2154
    if [[ -f "/usr/local/share/ca-certificates/ca.spacefx.local/ca.spacefx.local.crt" ]]; then
        if [[ ! -f "/etc/ssl/certs/ca.spacefx.local.pem" ]]; then
            run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem /etc/ssl/certs/ca.spacefx.local.pem"
        fi
        is_cmd_available "update-ca-certificates" has_cmd
        if [[ "${has_cmd}" == true ]]; then
            run_a_script "update-ca-certificates"
        fi
        return
    fi

    info_log "Deploying '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem' to trusted root authorities..."
    run_a_script "mkdir -p /usr/local/share/ca-certificates/ca.spacefx.local"

    run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt /usr/local/share/ca-certificates/ca.spacefx.local/ca.spacefx.local.crt" --disable_log
    run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem /etc/ssl/certs/ca.spacefx.local.pem" --disable_log

    info_log "...adding cert..."

    # Doing it this way lets us add to the host's chain incase we don't have update-ca-certificates
    run_a_script "cat ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt" space_fx_ca_cert --disable_log
    run_a_script "cat /etc/ssl/certs/ca-certificates.crt" current_ca_certs --disable_log

    run_a_script "tee /etc/ssl/certs/ca-certificates.crt > /dev/null << SPACEFX_UPDATE_END
${current_ca_certs}
${space_fx_ca_cert}
SPACEFX_UPDATE_END" --disable_log

    is_cmd_available "update-ca-certificates" has_cmd
    if [[ "${has_cmd}" == true ]]; then
        run_a_script "update-ca-certificates" --disable_log
    fi

    info_log "...successfully deployed '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem' to host..."

}

function add_hosts_entry_for_coresvc_registry(){
    # Calculate the external ip of the host by checking the routes used to get to the internet
    debug_log "Calculating external ip..."
    run_a_script_on_host "ip route get 8.8.8.8" host_ip
    host_ip=${host_ip#*src }
    host_ip=${host_ip%% *}

    debug_log "...external ip: '${host_ip}'"

    debug_log "...retrieving coresvc-registry external url..."

    run_a_script_on_host "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" _registry_url

    _registry_url="${_registry_url%%:*}"

    debug_log "...adding hosts entry for '${_registry_url}' to '${host_ip}'..."

    run_a_script "tee -a /etc/hosts > /dev/null << SPACEFX_UPDATE_END
${host_ip}       ${_registry_url}
SPACEFX_UPDATE_END" --disable_log

}

############################################################
# Check if a command is available
############################################################
function is_cmd_available() {
    if [[ "$#" -ne 2 ]]; then
        exit_with_error "Missing a parameter.  Please use function like is_cmd_available cmd_to_check result_variable"
    fi

    local cmd_to_test=$1
    local result_variable=$2
    local cmd_result="false"
    run_a_script "whereis -b ${cmd_to_test}" check_for_cmd --no_sudo --disable_log

    if [[ $check_for_cmd != "$cmd_to_test:" ]]; then
        eval "$result_variable='true'"
    else
        eval "$result_variable='false'"
    fi
}

function main() {
    initialize_spacedev_directory
    run_a_script_on_host "${SPACEFX_DIR}/scripts/stage_spacefx.sh"
    run_a_script_on_host "${SPACEFX_DIR}/scripts/deploy_spacefx.sh"
    add_ca_cert_to_trusted_root_authorities
    add_hosts_entry_for_coresvc_registry
}

main