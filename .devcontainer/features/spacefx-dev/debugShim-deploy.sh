#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md
# Deploys the debugshim into kubernetes and preps for a debugging session

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
DEBUG_SHIM_POD=""
PROCESS_PLUGIN_CONFIGS=true

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Checks if a debug shim is ready and if not, it's deployed and then waits"
   echo
   echo "Syntax: bash /spacefx-dev/debugShim-deploy.sh --debug_shim payload-app"
   echo "options:"
   echo "--debug_shim | -d                  [REQUIRED] The unique name to use for template generation"
   echo "--port | -p                        [REQUIRED FOR PYTHON] Port number used for port-forwarding start"
   echo "--python_file | -f                 [REQUIRED FOR PYTHON] Direct path to the python file we're debugging.  If omitted, the debugger is not started"
   echo "--disable_plugin_configs           [OPTIONAL] Skips the plugin secret update"
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
        -d|--debug_shim)
            shift
            DEBUG_SHIM=$1
            # Force to lower case
            DEBUG_SHIM=${DEBUG_SHIM,,}
            ;;
        --disable_plugin_configs)
            PROCESS_PLUGIN_CONFIGS=false
            ;;
        -f|--python_file)
            shift
            PYTHON_FILE=$1
            if [[ ! -f "${PYTHON_FILE}" ]]; then
                echo "Unable to find '${PYTHON_FILE}'.  Please check path and try again"
                show_help
            fi
            ;;
        -p|--port)
            shift
            PYTHON_PORT=$1
            if ! [[ $PYTHON_PORT =~ ^[0-9]+$ ]]; then
                echo "'${PYTHON_PORT}' is not a number.  Please update to pass a number only"
                show_help
            fi
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

if [[ "${DEV_LANGUAGE}" == "python" ]]; then
    if [[ -z "$PYTHON_PORT" ]]; then
        echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Missing --port parameter"
        show_help
    fi
    if [[ -z "$PYTHON_FILE" ]]; then
        echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Missing --python_file parameter"
        show_help
    fi
fi


source "${SPACEFX_DIR:?}/modules/load_modules.sh" $@ --log_dir "${SPACEFX_DIR:?}/logs/${APP_NAME:?}/${DEBUG_SHIM:?}"

############################################################
# Check for the debugshim pod and deploy if not found
############################################################
function verify_debugshim() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Verifying '${DEBUG_SHIM}' debugshim pod..."
    run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" DEBUG_SHIM_POD --ignore_error

    if [[ -z "${DEBUG_SHIM_POD}" ]]; then
        debug_log "Debug shim '${DEBUG_SHIM}' not found.  Provisioning from '${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml'"

        if [[ ! -f "${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml" ]]; then
            exit_with_error "'${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml' NOT FOUND...unable to provision debug shim.  Please rebuild your devcontainer"
        fi

        run_a_script "kubectl apply -f ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${DEBUG_SHIM}.yaml"

        trace_log "Waiting 2 seconds for deployment to take effect..."
        sleep 2

        info_log "Verifying '${DEBUG_SHIM}' debugshim pod..."
        run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" DEBUG_SHIM_POD
    fi
    info_log "Calculated as '${DEBUG_SHIM_POD}'.  Checking status..."

    run_a_script "kubectl get pod/${DEBUG_SHIM_POD} -n payload-app -o jsonpath='{.status.phase}'" DEBUG_SHIM_STATUS --disable_log

    info_log "...'${DEBUG_SHIM_POD}' Status: '${DEBUG_SHIM_STATUS}'"

    if [[ "${DEBUG_SHIM_STATUS}" != "Running" ]]; then
        info_log "Restarting '${DEBUG_SHIM}' debugshim pod..."
        run_a_script "kubectl delete pod/${DEBUG_SHIM_POD} -n payload-app"
        sleep 2

        run_a_script "kubectl get pods -n payload-app -l app=${DEBUG_SHIM} --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}'" DEBUG_SHIM_POD
    fi


    info_log "...successfully verified '${DEBUG_SHIM}' debugshim pod."

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Checks that the local configuration secret exists and creates it if it doesn't
############################################################
function verify_config_secret_exists() {
    info_log "START: ${FUNCNAME[0]}"
    # Check if a Kubernetes secret with the name `${targetService}-secret` exists in the `payload-app` namespace
    info_log "Verifying '${DEBUG_SHIM}' configuration secret '${DEBUG_SHIM}-secret'..."

    run_a_script "kubectl get secret/${DEBUG_SHIM}-secret -n payload-app -o json" has_config --ignore_error --disable_log

    # If the secret does not exist, create an empty secret with that name and a placeholder item
    # Empty secrets don't get applied the same way and this forces the volume to update in kubernetes
    if [[ -z "${has_config}" ]]; then
        debug_log "Not found.  Creating empty..."
        run_a_script "kubectl create secret generic ${DEBUG_SHIM}-secret \
                        -n payload-app \
                        --from-literal=placeholder=na" --disable_log
    fi

    # Log that the secret was found
    info_log "...successfully verified '${DEBUG_SHIM}' configuration secret '${DEBUG_SHIM}-secret'"
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


############################################################
# Pauses execution until the poststart flag is available
############################################################
function wait_for_poststart() {
    info_log "START: ${FUNCNAME[0]}"
    info_log "Checking for Devcontainer poststart flag ('/spacefx-dev/postStart.complete') (max ${MAX_WAIT_SECS} seconds)..."

    postStart_found=false

    start_time=$(date +%s)
    elapsed_time=0

    # This loops and waits for the debugshim_pod_ready to flip to true
    while [[ ${postStart_found} == false ]]; do

        [[ -f "/spacefx-dev/postStart.complete" ]] && postStart_found=true

        if [[ ! -f "/spacefx-dev/postStart.complete" ]]; then
            # Only output on even seconds so we don't flood the terminal with messages
            [ $((elapsed_time % 2)) -eq 0 ] && debug_log "...postStart flag '/spacefx-dev/postStart.complete' not available yet..."
            sleep 0.5
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for Devcontainer poststart flag ('/spacefx-dev/postStart.complete').  Check if an error has happened, or retry"
        fi
    done

    info_log "...Devcontainer postStart flag '/spacefx-dev/postStart.complete' found."

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Update the configuration to include the plugins (if any are present)
############################################################
function update_configuration_for_plugins() {
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${PROCESS_PLUGIN_CONFIGS}" == false ]]; then
        info_log "PROCESS_PLUGIN_CONFIGS = 'false'.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Scanning for plugin configuration files..."
    run_a_script "find ${CONTAINER_WORKING_DIR} -type f -name \"*.spacefx_plugin\" | head -n 1" plugin_file --ignore_error

    if [[ -z "${plugin_file}" ]]; then
        info_log "No plugin configuration files found.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "...found '${plugin_file}'.  Updating plugin directory to '${pluginPath}' for '${DEBUG_SHIM_POD}'...."

    pluginPath_encoded=$(echo -n "${plugin_file}" | base64)
    run_a_script "kubectl get secret/${DEBUG_SHIM}-secret -n payload-app -o json | jq '.data +={\"spacefx_dir_plugins\": \"${pluginPath_encoded}\"}' | kubectl apply -f -"
    debug_log "...successfully updated plugin directory to '${pluginPath}' for '${DEBUG_SHIM_POD}'"

    debug_log "...annotating '${DEBUG_SHIM_POD}' to trigger a faster secret update..."
    run_a_script "kubectl annotate pod ${DEBUG_SHIM_POD} -n payload-app kubernetes.io/change-cause='$(date)'"
    debug_log "...successfully annotated '${DEBUG_SHIM_POD}'"


    debug_log "...debug shim successfully updated for plugin debugging"



    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    wait_for_poststart

    verify_debugshim
    verify_config_secret_exists
    wait_for_debugshim_to_come_online
    update_configuration_for_plugins



    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main