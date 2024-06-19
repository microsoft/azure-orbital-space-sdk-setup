#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md
# Main entry point for the Microsoft Azure Orbital Space SDK Setup for devcontainers

#-------------------------------------------------------------------------------------------------------------
# Script initializing
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


set +e
#-------------------------------------------------------------------------------------------------------------

source "${SPACEFX_DIR:?}/modules/load_modules.sh" $@ --log_dir "${SPACEFX_DIR:?}/logs/${APP_NAME:?}"

# File pointers to let the rest of the container know we've started
run_a_script "touch /spacefx-dev/postStart.start"
[[ -f "/spacefx-dev/postStart.complete" ]] && run_a_script "rm /spacefx-dev/postStart.complete" --disable_log



############################################################
# Script variables
############################################################
STAGE_SPACE_FX_CMD_EXTRAS=""



############################################################
# Export parent service code from its base container if this is a plugin app
############################################################
function export_parent_service_binaries(){
    info_log "START: ${FUNCNAME[0]}"

    # Check if the app_type is "-plugin"
    if [[ ${APP_TYPE} != *"-plugin" ]]; then
        info_log "Not a plugin app type.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Checking for '${SVC_IMG}' binaries..."

    calculate_tag_from_channel --tag "${SPACEFX_VERSION}_base" --result _export_parent_service_binaries_tag

    if [[ ! -f "${SPACEFX_DIR}/tmp/${SVC_IMG}.tar" ]]; then
        info_log "'${SPACEFX_DIR}/tmp/${SVC_IMG}.tar' not found.  Exporting registry.spacefx.local/${SVC_IMG}:${_export_parent_service_binaries_tag} to ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar..."
        run_a_script "regctl image export registry.spacefx.local/${SVC_IMG}:${_export_parent_service_binaries_tag} ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar"
        info_log "...successfully exported parent service binaries from '${SVC_IMG}'"
    fi

    info_log "...'${SVC_IMG}' binaries found at '${SPACEFX_DIR}/tmp/${SVC_IMG}.tar'"

    if [[ ! -d "${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG}" ]]; then
        info_log "Extracting '${SPACEFX_DIR}/tmp/${SVC_IMG}.tar' to ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG}"

        # Rebuild the image filesystem by enumerates the manifest.json file and extracting each layer in order
        run_a_script "mktemp -d" _image_export_dir --disable_log
        run_a_script "tar -xvf ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar -C ${_image_export_dir}"

        run_a_script "mktemp -d" _image_rebuild --disable_log
        _svc_layers=$(jq -r '.[].Layers[]' "$_image_export_dir/manifest.json")

        for _svc_layer in $_svc_layers; do
            run_a_script "tar -xf ${_image_export_dir}/${_svc_layer} -C ${_image_rebuild}"
        done

        create_directory "${CONTAINER_WORKING_DIR}/.git/workspaces"
        run_a_script "cp ${_image_rebuild}/workspaces/${SVC_IMG} ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG} -r"
    fi


    info_log "...successfully extracted '${SVC_IMG}' binaries to ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG}"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Install Dotnet
############################################################
function check_and_install_dotnet(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for dotnet ('${DOTNET_INSTALL_DIR:?}/dotnet')..."
    if [[ ! -f "${DOTNET_INSTALL_DIR:?}/dotnet" ]]; then
        info_log "...dotnet not found.  Downloading..."
        run_a_script "wget -P /tmp -q https://dotnet.microsoft.com/download/dotnet/scripts/v1/dotnet-install.sh" --disable_log
        run_a_script "chmod +x /tmp/dotnet-install.sh" --disable_log
        run_a_script "/tmp/dotnet-install.sh --version ${DOTNET_SDK_VERSION:?}" --disable_log
    fi

    info_log "...dotnet found at '${DOTNET_INSTALL_DIR:?}/dotnet'"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Install VSDebugger
############################################################
function check_and_install_vsdebugger(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for VSDebugger ('${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/vsdbg/vsdbg')..."
    if [[ ! -f "${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/vsdbg/vsdbg" ]]; then
        info_log "...VSDebugger not found.  Downloading..."

        run_a_script "wget -P /tmp -q https://aka.ms/getvsdbgsh" --disable_log
        run_a_script "chmod +x /tmp/getvsdbgsh" --disable_log
        run_a_script "mkdir -p ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/vsdbg" --disable_log
        run_a_script "/tmp/getvsdbgsh -v latest -l ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/vsdbg"
    fi

    info_log "...VSDebugger found at '${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/vsdbg/vsdbg'"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Add the local nuget source to dotnet's list of sources
############################################################
function add_spacedev_nuget_source(){
    info_log "START: ${FUNCNAME[0]}"

    create_directory "${SPACEFX_DIR}/nuget"

    run_a_script "${DOTNET_INSTALL_DIR:?}/dotnet nuget list source" current_nuget_sources

    if [[ $current_nuget_sources == *"${SPACEFX_DIR}/nuget"* ]]; then
        info_log "found nuget source '${SPACEFX_DIR}/nuget'.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Adding '${SPACEFX_DIR}/nuget' as a nuget source..."
    run_a_script "${DOTNET_INSTALL_DIR:?}/dotnet nuget add source ${SPACEFX_DIR}/nuget"
    info_log "...successfully added '${SPACEFX_DIR}/nuget'"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Remove the contents of bin and object directories so we always start fresh
############################################################
function wipe_bin_and_obj_directories() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Removing obj and bin directories..."

    while IFS= read -r -d '' dir; do
        debug_log "Removing '${dir}'..."
        run_a_script "rm ${dir} -rf"
        debug_log "...done."
    done < <(find "${CONTAINER_WORKING_DIR}" -iname "bin" -o -iname "obj" -type d -print0)

    info_log "...obj and bin directories removed"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Loop through the debugshims that were requested and generate them
############################################################
function generate_debugshims(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ -n "${DEBUG_SHIM_PRE_YAML_FILE}" ]]; then
        info_log "Running DEBUG_SHIM_PRE_YAML_FILE '${DEBUG_SHIM_PRE_YAML_FILE}'..."
        if [[ ! -f "${DEBUG_SHIM_PRE_YAML_FILE}" ]]; then
            exit_with_error "Unable to find DEBUG_SHIM_PRE_YAML_FILE '${DEBUG_SHIM_PRE_YAML_FILE}'.  Check path and try again"
        fi
        run_a_script "kubectl apply -f ${DEBUG_SHIM_PRE_YAML_FILE}"
    fi

    for debug_shim in "${DEBUG_SHIMS[@]}"; do
        if [[ "$debug_shim" == "$APP_NAME"* ]]; then
            generate_debugshim --debug_shim "${debug_shim}"
        else
            generate_debugshim --debug_shim "${APP_NAME}-${debug_shim}"
        fi
    done


    if [[ -n "${DEBUG_SHIM_POST_YAML_FILE}" ]]; then
        info_log "Running DEBUG_SHIM_POST_YAML_FILE '${DEBUG_SHIM_POST_YAML_FILE}'..."
        if [[ ! -f "${DEBUG_SHIM_POST_YAML_FILE}" ]]; then
            exit_with_error "Unable to find DEBUG_SHIM_POST_YAML_FILE '${DEBUG_SHIM_POST_YAML_FILE}'.  Check path and try again"
        fi
        run_a_script "kubectl apply -f ${DEBUG_SHIM_POST_YAML_FILE}"
    fi

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Generate a debum shim
############################################################
function generate_debugshim(){
    info_log "START: ${FUNCNAME[0]}"
    local debug_shim=""
    local extra_cmd=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --debug_shim)
            shift
            debug_shim=$1
            ;;
        esac
        shift
    done

    [[ -z "${debug_shim}" ]] && exit_with_error "--debug_shim is required for generate_debugshim function"

    info_log "Generating debugshim for '${debug_shim}'..."

    debug_log "Removing any prior deployments of '${debug_shim}'..."
    remove_deployment_by_app_id --app_id "${debug_shim}"
    wait_for_deployment_deletion_by_app_id --app_id "${debug_shim}"

    run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart \
        ${extra_cmd} \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.appName=${debug_shim} \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.enabled=true \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.debugShim=true \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.serviceNamespace=payload-app \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.provisionVolumeClaims=true         \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.provisionVolumes=true         \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.workingDir=${CONTAINER_WORKING_DIR} \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.repository=${CONTAINER_IMAGE} \
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.hostSourceCodeDir=${HOST_FOLDER}" yaml

    run_a_script "tee ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${debug_shim}.yaml > /dev/null << SPACEFX_UPDATE_END
${yaml}
SPACEFX_UPDATE_END"


    check_service_account $debug_shim
    check_fileserver_creds $debug_shim

    run_a_script "kubectl apply -f ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${debug_shim}.yaml"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Check if the service account exists in the payload namespace.  If not, create it
############################################################
function check_service_account(){
    info_log "START: ${FUNCNAME[0]}"

    local appName=$1

    debug_log "Validating service account '${appName}' exists in payload-app..."
    run_a_script "kubectl get serviceaccount -A -o json | jq '.items[] | select(.metadata.name == \"${appName}\" and .metadata.namespace == \"payload-app\") | true'" service_account

    debug_log "Service_account: ${service_account}"

    if [[ -z "${service_account}" ]]; then
        debug_log "...not found.  Creating service account '${appName}' in payload-app..."
        run_a_script "kubectl create serviceaccount ${appName} -n payload-app"
        debug_log "...successfully creatied service account '${appName}'."
    else
        debug_log "...found service account '${appName}' in payload-app"
    fi

    debug_log "Successfully validated service account '${appName}'"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Check if core-fileserver has creds provisioned for this debug shim
############################################################
function check_fileserver_creds(){
    info_log "START: ${FUNCNAME[0]}"

    local appName=$1

    info_log "Validating FileServer credentials for '${appName}'..."

    run_a_script "kubectl get secrets -A -o json | jq -r '.items[] | select(.metadata.name == \"fileserver-${appName}\" and (.metadata.namespace == \"payload-app\")) | true'" has_creds --disable_log

    if [[ "${has_creds}" == "true" ]]; then
        info_log "Found previous credentials.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "No previous credentials found.  Generating..."

    run_a_script "kubectl get secrets -A -o json | jq -r '.items[] | select(.metadata.name == \"fileserver-${appName}\" and (.metadata.namespace == \"hostsvc\" or .metadata.namespace == \"platformsvc\")) | @base64'" service_creds --disable_log

    if [[ -n "${service_creds}" ]]; then
        parse_json_line --json "${service_creds}" --property ".metadata.namespace" --result creds_namespace
        info_log "...previous service credentials found for '${appName}' in namespace '${creds_namespace}'.  Copying to 'payload-app'..."
        run_a_script "kubectl get secret/fileserver-${appName} -n ${creds_namespace} -o yaml | yq 'del(.metadata.annotations) | del(.metadata.creationTimestamp) | del(.metadata.resourceVersion) | del(.metadata.uid) | .metadata.namespace = \"payload-app\"'" creds_yaml --disable_log
        run_a_script "kubectl apply -f - <<SPACEFX_UPDATE_END
${creds_yaml}
SPACEFX_UPDATE_END" --disable_log

        info_log "...Successfully copied secret '${appName}' to 'payload-app'."
    else
        info_log "...No previous fileserver credentials found for '${appName}'.  Generating..."
        add_fileserver_creds ${appName}
    fi

    info_log "Successfully validated service account '${appName}'"



    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Adds a new credential for file server
############################################################
function add_fileserver_creds(){
    info_log "START: ${FUNCNAME[0]}"

    local appName=$1

    info_log "Provisioning new fileserver credentials for '${appName}'..."
    CHARSET="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    run_a_script "head /dev/urandom | tr -dc \"${CHARSET}\" | head -c 16 | base64" generated_password  --disable_log
    run_a_script "base64 <<< ${appName}" generated_username --disable_log

    run_a_script "kubectl get secret/coresvc-fileserver-config -n coresvc -o json | jq '.data +={\"user-${appName}\": \"${generated_password}\"}'  | kubectl apply -f -" --disable_log

    run_a_script "kubectl apply -f - <<SPACEFX_UPDATE_END
apiVersion: v1
kind: Secret
metadata:
  name: fileserver-${appName}
  namespace: payload-app
type: Opaque
data:
  username: ${generated_username}
  password: ${generated_password}
SPACEFX_UPDATE_END" --disable_log



    info_log "...successfully provisioned new fileserver credentials '${appName}'"

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    check_and_install_dotnet
    check_and_install_vsdebugger

    add_spacedev_nuget_source
    wipe_bin_and_obj_directories

    if [[ "${CLUSTER_ENABLED}" == true ]] && [[ "${DEBUG_SHIM_ENABLED}" == true ]]; then
        [[ ! -d "${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev" ]] && run_a_script "mkdir -p ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev" --disable_log
        [[ ! -f "${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/debugShim_keepAlive.sh" ]] && run_a_script "cp /spacefx-dev/debugShim_keepAlive.sh ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/debugShim_keepAlive.sh" --disable_log
        generate_debugshims
        export_parent_service_binaries
        # run_user_requested_yamls
    fi

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}

main
run_a_script "touch /spacefx-dev/postStart.complete" --disable_log