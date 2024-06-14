#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md
# Resets the debug shim for the Microsoft Azure Orbital Space SDK Setup for devcontainers and preps for another debugging iteration

#-------------------------------------------------------------------------------------------------------------
# Script initializing
set -e

# If we're running in the devcontainer with the k3s-on-host feature, source the .env file
[[ -f "/devfeature/k3s-on-host/.env" ]] && source /devfeature/k3s-on-host/.env

# Pull in the app.env file built by the feature
[[ -n "${SPACEFX_DEV_ENV}" ]] && [[ -f "${SPACEFX_DEV_ENV}" ]] && source "${SPACEFX_DEV_ENV:?}"


set +e
#-------------------------------------------------------------------------------------------------------------



############################################################
# Script variables
############################################################
DEBUG_SHIM=""
PREVIOUS_DEBUG_SHIM_POD=""
WAIT_FOR_POD=true

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Checks if a debug shim is ready and if not, it's deployed and then waits"
   echo
   echo "Syntax: bash /spacefx-dev/debugShim-reset.sh --debug_shim payload-app"
   echo "options:"
   echo "--debug_shim | -d                  [REQUIRED] The unique name to use for template generation"
   echo "--skip-pod-wait | -w               [OPTIONAL] Skips waiting for the new pod to come online"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        -w|--skip-pod-wait)
            WAIT_FOR_POD=false
            ;;
        -d|--debug_shim)
            shift
            DEBUG_SHIM=$1
            # Force to lower case
            DEBUG_SHIM=${DEBUG_SHIM,,}
            ;;
        *) echo "Unknown parameter passed: $1"; show_help;;
    esac
    shift
done

if [[ -z "$SPACESDK_CONTAINER" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Devcontainer was not detected.  This script must be run from a Devcontainer"
    show_help
fi

if [[ -z "$DEBUG_SHIM" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Mising --debug_shim parameter"
    show_help
fi

source "${SPACEFX_DIR:?}/modules/load_modules.sh" $@ --log_dir "${SPACEFX_DIR:?}/logs/${APP_NAME:?}/${DEBUG_SHIM:?}"

############################################################
# Reset Debug Shim
############################################################
function reset_debugshim() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Determining previous debug shim name..."
    run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" PREVIOUS_DEBUG_SHIM_POD --ignore_error
    info_log "Calculated as '${PREVIOUS_DEBUG_SHIM_POD}'"

    info_log "Resetting spacefx_dir_plugins"
    pluginPath_encoded=$(echo -n "${SPACEFX_DIR}/plugins/${DEBUG_SHIM}" | base64)
    run_a_script "kubectl get secret/${DEBUG_SHIM}-secret -n payload-app -o json | jq '.data +={\"spacefx_dir_plugins\": \"${pluginPath_encoded}\"}' | kubectl apply -f -"

    info_log "Deleting '${PREVIOUS_DEBUG_SHIM_POD}'..."
    run_a_script "kubectl delete pod/${PREVIOUS_DEBUG_SHIM_POD} -n payload-app --wait=false"

    # if [[ ! -f "${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml" ]]; then
    #     exit_with_error "'${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml' NOT FOUND...unable to provision debug shim.  Please rebuild your devcontainer"
    # fi

    # info_log "Removing previous secret '${DEBUG_SHIM}-secret'..."
    # run_a_script "kubectl delete secret/${DEBUG_SHIM}-secret -n payload-app" --ignore_error
    # info_log "...successfully removed previous secret '${DEBUG_SHIM}-secret'"

    # if [[ -n "${PREVIOUS_DEBUG_SHIM_POD}" ]]; then
    #     info_log "Removing previous deployment of '${DEBUG_SHIM}'..."
    #     run_a_script "kubectl delete deployment/${DEBUG_SHIM} -n payload-app"
    #     info_log "...successfully removed previous deployment of '${DEBUG_SHIM}'."
    # else
    #     info_log "Previous debug shim not found.  Nothing to remove"
    # fi

    # info_log "Deploying '${DEBUG_SHIM}'..."
    # run_a_script "kubectl apply -f ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml --selector=app=${DEBUG_SHIM},type=Deployment"
    # run_a_script "kubectl apply -f ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml --selector=app=${DEBUG_SHIM},type=Secret"
    # info_log "...successfully deployed '${DEBUG_SHIM}'."

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Pauses execution until the debugshim pod is running and reach
############################################################
function wait_for_debugshim_to_come_online() {
    info_log "START: ${FUNCNAME[0]}"
    info_log "Waiting for '${DEBUG_SHIM}' debugshim pod to come online (max ${MAX_WAIT_SECS} seconds)..."

    debugshim_pod_ready=false
    start_time=$(date +%s)
    elapsed_time=0

    info_log "...waiting for new new debugshim pod to start provisioning..."

    run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" DEBUG_SHIM_POD --ignore_error
    while [[ "${DEBUG_SHIM_POD}" == "${PREVIOUS_DEBUG_SHIM_POD}" ]]; do

        run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" DEBUG_SHIM_POD --ignore_error

        if [[ "${DEBUG_SHIM_POD}" == "${PREVIOUS_DEBUG_SHIM_POD}" ]]; then
            # Only output on even seconds so we don't flood the terminal with messages
            [ $((elapsed_time % 2)) -eq 0 ] && debug_log "...'${DEBUG_SHIM}' debugshim pod has not provisioned yet..."
            sleep 0.5
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for debugshim pod '${DEBUG_SHIM}' to come online.  Check if an error has happened, or retry"
        fi

    done


    # This loops and waits for the debugshim_pod_ready to flip to true
    while [[ ${debugshim_pod_ready} == false ]]; do

        run_a_script "kubectl exec ${DEBUG_SHIM_POD} -n payload-app -- bash -c 'echo Container Ready'" echo_check --ignore_error

        if [[ "${echo_check}" == "Container Ready" ]]; then
            debugshim_pod_ready=true
        else
            # Only output on even seconds so we don't flood the terminal with messages
            [ $((elapsed_time % 2)) -eq 0 ] && debug_log "...'${DEBUG_SHIM}' debugshim pod not ready yet..."
            sleep 0.5
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for debugshim pod '${DEBUG_SHIM}' to come online.  Check if an error has happened, or retry"
        fi

    done

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    reset_debugshim

    if [[ "${WAIT_FOR_POD}" == true ]]; then
        wait_for_debugshim_to_come_online
    else
        info_log "WAIT_FOR_POD = '${WAIT_FOR_POD}'.  Skipping wait"
    fi



    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main