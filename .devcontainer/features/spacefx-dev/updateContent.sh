#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md
# Main entry point for the Microsoft Azure Orbital Space SDK Setup for devcontainers

#-------------------------------------------------------------------------------------------------------------
# Setup and populate the spacedev directory on the host before we can do anything else


# Only run as the root user
if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Setup the directory on the host so we can copy our files over to it
set -e

# If we're running in the devcontainer with the k3s-on-host feature, source the .env file
[[ -f "/devfeature/k3s-on-host/.env" ]] && source /devfeature/k3s-on-host/.env

# Pull in the app.env file built by the feature
[[ -n "${SPACEFX_DEV_ENV}" ]] && [[ -f "${SPACEFX_DEV_ENV}" ]] && source "${SPACEFX_DEV_ENV:?}"

## Create the spacefx-dev directory on the host if it doesn't exist
[[ ! -d "${SPACEFX_DIR_FOR_HOST:?}" ]] && mkdir -p "${SPACEFX_DIR_FOR_HOST:?}"

## Create a symlink on the devcontainer to the host directory so the directory paths match on both
[[ ! -L "${SPACEFX_DIR}" ]] && ln -s "${SPACEFX_DIR_FOR_HOST:?}" "${SPACEFX_DIR:?}"

## Provision the spacefx-dev directory with the latest files from spacesdk-setup
cp /azure-orbital-space-sdk-setup/* "${SPACEFX_DIR_FOR_HOST:?}" -r
set +e

# Directory is setup and populated.  Now we can run the main script
#-------------------------------------------------------------------------------------------------------------


source "${SPACEFX_DIR:?}/modules/load_modules.sh" $@ --log_dir "${SPACEFX_DIR:?}/logs/${APP_NAME:?}"

# File pointers to let the rest of the container know we've started
run_a_script "touch /spacefx-dev/updateContent.start" --disable_log
if [[ -f "/spacefx-dev/updateContent.complete" ]]; then
    run_a_script "rm /spacefx-dev/updateContent.complete" --disable_log
fi

if [[ -f "/spacefx-dev/debugShim.start" ]]; then
    run_a_script "rm /spacefx-dev/debugShim.complete" --disable_log
fi

if [[ -f "/spacefx-dev/debugShim.start" ]]; then
    run_a_script "rm /spacefx-dev/debugShim.complete" --disable_log
fi


############################################################
# Script variables
############################################################
STAGE_SPACE_FX_CMD_EXTRAS=""

############################################################
# Function Template
############################################################
function _template(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Download any configuration yaml specificed in the devcontainer options and trigger a spacefx-config.json regen
############################################################
function pull_config_yamls(){
    info_log "START: ${FUNCNAME[0]}"





    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Add any extra containers passed from the devcontainer.json to the stage cmd
############################################################
function pull_extra_containers(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ${#PULL_CONTAINERS[@]} -eq 0 ]]; then
        info_log "...no containers specified in devcontainer.json.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    for container in "${CONTAINERS[@]}"; do
        if [[ -z "${container}" ]]; then
            continue
        fi
        info_log "...adding container '${container}' to stage_spacefx cmd..."
        STAGE_SPACE_FX_CMD_EXTRAS="${STAGE_SPACE_FX_CMD_EXTRAS} --container ${container}"
    done

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# If we're building a plugin, we need to get the main service bits to debugging
############################################################
function export_parent_service_container(){
    info_log "START: ${FUNCNAME[0]}"

    # Check and add the CONTAINER_IMAGE to the dev env file
    if [[ "$APP_TYPE" != *"plugin"* ]]; then
        info_log "App Type '${APP_TYPE}' doesn't have a parent service.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    #TODO: Add functionality to get the parent service and export

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Add any extra packages passed from the devcontainer.json and install them
############################################################
function install_extra_packages(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ${#EXTRA_PACKAGES[@]} -eq 0 ]]; then
        info_log "...no packages to install.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Installing packages '${EXTRA_PACKAGES[*]}'..."
    run_a_script "apt-get update \
                    && apt-get install -y --no-install-recommends ${EXTRA_PACKAGES[*]}"
    info_log "...packages successfully installed"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Calculate the helm service group based on the app type
############################################################
function calculate_helm_groups(){
    info_log "START: ${FUNCNAME[0]}"

    HELM_SVC_NAME=payloadapp
    HELM_SVC_GROUP=payloadapp

    # Calculate the service group and service name if it's not one of the default ones
    if ! [[ "${APP_TYPE}" =~ ^(spacesdk-core|payloadapp|sdk)$ ]]; then
        run_a_script "yq '.' --output-format=json ${SPACEFX_DIR}/chart/values.yaml | jq -r ' .services[] | to_entries[] | select(.value.appName == \"${SVC_IMG}\") | .key'" HELM_SVC_NAME
        run_a_script "yq '.' --output-format=json ${SPACEFX_DIR}/chart/values.yaml | jq -r ' .services | to_entries[] | select(.value | has(\"${HELM_SVC_NAME}\")) | .key'" HELM_SVC_GROUP
    fi

    run_a_script "tee -a ${SPACEFX_DEV_ENV:?} > /dev/null << SPACEFX_END
export HELM_SVC_NAME=${HELM_SVC_NAME}
export HELM_SVC_GROUP=${HELM_SVC_GROUP}
SPACEFX_END" --disable_log

    write_parameter_to_log HELM_SVC_NAME
    write_parameter_to_log HELM_SVC_GROUP


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Add a symlink to spacedev to make it easy to view what's happening in the devcontainer
############################################################
function add_symlink_to_spacedev() {
    # Check if the symlink exists
    if [ -L "${CONTAINER_WORKING_DIR}/spacedev_cache" ]; then
        # If the symlink exists, check if it's pointing to the correct source path
        if [ "$(readlink "${CONTAINER_WORKING_DIR}/spacedev_cache")" != "${SPACEFX_DIR}" ]; then
            # If the symlink is pointing to the wrong source path, remove it and create a new one
            run_a_script "rm '${CONTAINER_WORKING_DIR}/spacedev_cache'"
            run_a_script "ln -s '${SPACEFX_DIR}' '${CONTAINER_WORKING_DIR}/spacedev_cache'"
        fi
    else
        # If the symlink doesn't exist, create a new one
        run_a_script "ln -s '${SPACEFX_DIR}' '${CONTAINER_WORKING_DIR}/spacedev_cache'"
    fi
}



function main() {
    install_extra_packages

    if [[ "${CLUSTER_ENABLED}" == "false" ]]; then
        return
    fi

    add_symlink_to_spacedev
    calculate_helm_groups
    pull_config_yamls
    pull_extra_containers
    info_log "Starting stage_spacefx.sh..."
    run_a_script_on_host "${SPACEFX_DIR}/scripts/stage_spacefx.sh ${STAGE_SPACE_FX_CMD_EXTRAS}"
    info_log "...stage_spacefx.sh completed successfully"
    info_log "Starting deploy_spacefx.sh..."
    run_a_script_on_host "${SPACEFX_DIR}/scripts/deploy_spacefx.sh"
    info_log "...deploy_spacefx.sh completed successfully"


    export_parent_service_container

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}

main
run_a_script "touch /spacefx-dev/updateContent.complete" --disable_log