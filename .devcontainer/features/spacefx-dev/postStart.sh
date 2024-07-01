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

    info_log "Exporting '${SVC_IMG}' binaries..."

    calculate_tag_from_channel --tag "${SPACEFX_VERSION}_base" --result _export_parent_service_binaries_tag

    # Remove any old instances to ensure we're running the most recent version
    [[ -f "${SPACEFX_DIR}/tmp/${SVC_IMG}.tar" ]] && run_a_script "rm ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar"
    [[ -d "${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG}" ]] && run_a_script "rm ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG} -rf"


    info_log "Exporting registry.spacefx.local/${SVC_IMG}:${_export_parent_service_binaries_tag} to ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar..."
    run_a_script "regctl image export registry.spacefx.local/${SVC_IMG}:${_export_parent_service_binaries_tag} ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar"
    info_log "...successfully exported parent service binaries from '${SVC_IMG}'"

    info_log "Extracting '${SPACEFX_DIR}/tmp/${SVC_IMG}.tar' to ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG}"
    debug_log "Rebuilding '${SVC_IMG}' image filesystem..."

    # Rebuild the image filesystem by enumerating the manifest.json file and extracting each layer in order
    run_a_script "mktemp -d" _image_export_dir --disable_log
    run_a_script "tar -xvf ${SPACEFX_DIR}/tmp/${SVC_IMG}.tar -C ${_image_export_dir}" --disable_log

    run_a_script "mktemp -d" _image_rebuild --disable_log
    _svc_layers=$(jq -r '.[].Layers[]' "$_image_export_dir/manifest.json")

    for _svc_layer in $_svc_layers; do
        run_a_script "tar -xf ${_image_export_dir}/${_svc_layer} -C ${_image_rebuild}"
    done

    create_directory "${CONTAINER_WORKING_DIR}/.git/workspaces"
    run_a_script "cp ${_image_rebuild}/workspaces/${SVC_IMG} ${CONTAINER_WORKING_DIR}/.git/workspaces/${SVC_IMG} -r"

    # Cleanup
    run_a_script "rm ${_image_export_dir} -rf"
    run_a_script "rm ${_image_rebuild} -rf"

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

    if [[ ! -f "/usr/local/bin/dotnet" ]] && [[ ! -L "/usr/local/bin/dotnet" ]]; then
        run_a_script "ln -s ${DOTNET_INSTALL_DIR:?}/dotnet /usr/local/bin/dotnet"
    fi

    info_log "...dotnet found at '${DOTNET_INSTALL_DIR:?}/dotnet'"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Copy the space SDK wheel (if applicable)
############################################################
function python_copy_spacesdk_wheel(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${DEV_PYTHON}" != "true" ]]; then
        info_log "Python not found.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Python detected (DEV_PYTHON=true)"

    info_log "Searching and removing any poetry.lock files..."
    run_a_script "find ${CONTAINER_WORKING_DIR} -name 'poetry.lock' -type f" poetry_lock_files

    for poetry_lock_file in $poetry_lock_files; do
        info_log "...removing '${poetry_lock_file}'..."
        run_a_script "rm -f ${poetry_lock_file}"
        info_log "...successfully removed '${poetry_lock_file}..."
    done

    info_log "...successfully removed all poetry.lock files"

    # Python SDK doesn't get the wheel because it's the wheel builder
    if [[ "${APP_TYPE}" != "spacesdk-client" ]]; then
        info_log "Copying wheel from '${SPACEFX_DIR}/wheel/microsoftazurespacefx/microsoftazurespacefx-*-py3-none-any.whl' to '${CONTAINER_WORKING_DIR}/.wheel'..."

        create_directory "${CONTAINER_WORKING_DIR}/.wheel"
        run_a_script "cp ${SPACEFX_DIR}/wheel/microsoftazurespacefx/microsoftazurespacefx-*-py3-none-any.whl ${CONTAINER_WORKING_DIR}/.wheel"

        info_log "...successfully copied wheel from '${SPACEFX_DIR}/wheel/microsoftazurespacefx/microsoftazurespacefx-*-py3-none-any.whl' to '${CONTAINER_WORKING_DIR}/.wheel'"
    fi



    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Install Apps used by Python
############################################################
function python_check_dev_app_dependencies(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for poetry..."
    is_cmd_available "poetry" has_cmd
    if [[ "${has_cmd}" == false ]]; then
        info_log "Poetry not found.  Installing..."
        run_a_script "curl -sSL https://install.python-poetry.org | POETRY_HOME=/root/.local python3 -"
        run_a_script "chmod +x /root/.local/bin/poetry"
        run_a_script "/root/.local/bin/poetry config virtualenvs.create false"
    fi

    info_log "Poetry found...setting config to '${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pypoetry'..."
    create_directory "${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pypoetry"
    run_a_script "/root/.local/bin/poetry config cache-dir ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pypoetry"
    info_log "...poetry successfully installed."

    info_log "Updating pip cache to '${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pip'..."
    create_directory "${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pip"
    run_a_script "tee /etc/pip.conf > /dev/null << PIP_UPDATE_END
[global]
cache-dir = ${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pip
PIP_UPDATE_END"
    info_log "...successfully updated pip cache to '${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/pip'."

    info_log "Installing remarshal..."
    run_a_script "pip install remarshal"
    info_log "...successfully installed remarshal"

    info_log "Installing socat to host (if missing)..."
    run_a_script_on_host "apt-get install -y --no-install-recommends socat"
    info_log "...successfully installed socat"


    python_check_pyproject_toml


    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Install Poetry for python apps
############################################################
function python_poetry_install(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ! -f "${CONTAINER_WORKING_DIR:?}/pyproject.toml" ]]; then
        warn_log "No '${CONTAINER_WORKING_DIR:?}/pyproject.toml' found.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    local extra_cmd=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --no-root)
                extra_cmd="${extra_cmd} --no-root"
                ;;
            --no-spacefx-dev)
                extra_cmd="${extra_cmd} --without spacefx-dev"
                ;;
            --all-extras)
                extra_cmd="${extra_cmd} --all-extras"
                ;;
        esac
        shift
    done

    run_a_script "/root/.local/bin/poetry install ${extra_cmd}"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Python dependency installs
############################################################
function python_check_pyproject_toml(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${APP_TYPE}" != "payloadapp" ]]; then
        info_log "Dev Dependency checks only apply to Payload Apps.  '${APP_TYPE}' is not 'payloadapp'.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    local PYPROJECT_TOML_PATH="${CONTAINER_WORKING_DIR}/pyproject.toml"
    local PYPROJECT_JSON_PATH="${SPACEFX_DIR}/tmp/${APP_NAME}/pyproject.json"
    local REQUIRED_DEPENDENCIES_TOML_PATH="/spacefx-dev/spacefx.toml"
    local REQUIRED_DEPENDENCIES_JSON_PATH="${SPACEFX_DIR}/tmp/${APP_NAME}/spacefx.json"

    pyproject_toml_out_of_date=false

    create_directory "${SPACEFX_DIR}/tmp/${APP_NAME}"

    [[ -f "${PYPROJECT_JSON_PATH}" ]] && run_a_script "rm ${PYPROJECT_JSON_PATH}"
    [[ -f "${REQUIRED_DEPENDENCIES_JSON_PATH}" ]] && run_a_script "rm ${REQUIRED_DEPENDENCIES_JSON_PATH}"

    # Check if the pyproject.toml file exists
    if [[ ! -f "${PYPROJECT_TOML_PATH}" ]]; then
        exit_with_error "pyproject.toml not found at '${PYPROJECT_TOML_PATH}'."
    fi

    # Check if the required dependencies file exists
    if [[ ! -f "${REQUIRED_DEPENDENCIES_TOML_PATH}" ]]; then
        exit_with_error "Required dependencies file not found at '${REQUIRED_DEPENDENCIES_TOML_PATH}'."
    fi

    write_parameter_to_log AUTO_INJECT_PYTHON_DEV_DEPENDENCIES

    info_log "Running dependency check against ${PYPROJECT_TOML_PATH}..."

    debug_log "Converting ${PYPROJECT_TOML_PATH} and ${REQUIRED_DEPENDENCIES_TOML_PATH} to JSON at '${PYPROJECT_JSON_PATH}' and '${REQUIRED_DEPENDENCIES_JSON_PATH}'..."
    # Convert both TOML files to JSON
    run_a_script "remarshal -if toml -of json ${PYPROJECT_TOML_PATH} ${PYPROJECT_JSON_PATH}"
    run_a_script "remarshal -if toml -of json ${REQUIRED_DEPENDENCIES_TOML_PATH} ${REQUIRED_DEPENDENCIES_JSON_PATH}"
    debug_log "...successfully converted ${PYPROJECT_TOML_PATH} and ${REQUIRED_DEPENDENCIES_TOML_PATH} to JSON"

    # Find the paths of all scalar values in the reference JSON file - this essentially flattens all the paths in the JSON file
    run_a_script "jq -r 'paths(scalars) | join(\".\")' ${REQUIRED_DEPENDENCIES_JSON_PATH}" required_dependencies

    # Store the JSON contents in memory so we can access it faster
    run_a_script "cat ${PYPROJECT_JSON_PATH}" pyproject_json
    run_a_script "cat ${REQUIRED_DEPENDENCIES_JSON_PATH}" reqd_json

    # Loop through all paths in the reference JSON and add them to the project JSON if they don't already exist
    for path in $required_dependencies; do
        # store the non-converted path for use later
        orig_path="${path}"

        # Convert the path from a.b.c.d to ["a"].["b"].["c"].["d"] to make it json safe
        path="${path//./\"].[\"}"
        path="[\"${path}\"]"

        # Query the value in both the project and reference JSON files
        run_a_script "jq -r '.$path'  <<< \$reqd_json" reqd_value
        run_a_script "jq -r '.$path'  <<< \${pyproject_json}" proj_value

        # The values differ between the project and reference JSON files
        if [[ "${proj_value}" != "${reqd_value}" ]]; then
            warn_log "Detected a missing / out-of-date dependency in '${PYPROJECT_TOML_PATH}': '${orig_path}' = '${proj_value}'.  Required value: '${reqd_value}'."
            pyproject_toml_out_of_date=true

            # Let the dev know they need to update something
            if [[ "${AUTO_INJECT_PYTHON_DEV_DEPENDENCIES}" == false ]]; then
                run_a_script "cat ${REQUIRED_DEPENDENCIES_TOML_PATH}" required_dependencies_toml
                warn_log "Detected missing dependencies and auto_inject_python_dev_dependencies = 'false'.   To auto-inject, set auto_inject_python_dev_dependencies = 'true' in your devcontainer.json file."
                exit_with_error "Detected missing dependencies. Please add the following dependencies to your pyproject.toml file:\n\n${required_dependencies_toml}\n\nThen rebuild your devcontainer."
            fi

            # This gets the parent path without the last leaf (i.e. the ["a"].["b"].["c"] if the full path is ["a"].["b"].["c"].["d"])
            parent_path="${path%.*}"

            # Orig_path is a.b.c.d.  This get the last item (i.e. d) and the += is already json safe, so we don't need to escape it
            key="${orig_path##*.}"

            info_log "AUTO_INJECT_PYTHON_DEV_DEPENDENCIES = 'true'.  Updating '${PYPROJECT_TOML_PATH}': '${orig_path}' to '${reqd_value}'."
            run_a_script "jq '.$parent_path += {\"$key\": \"$reqd_value\"}' <<< \${pyproject_json}" pyproject_json
            info_log "...successfully updated '${PYPROJECT_TOML_PATH}': '${orig_path}' to '${reqd_value}'."
        fi
    done

    if [[ "${pyproject_toml_out_of_date}" == false ]]; then
        info_log "All dependencies verified.  Nothing to do"
        [[ -f "${PYPROJECT_JSON_PATH}" ]] && run_a_script "rm ${PYPROJECT_JSON_PATH}"
        [[ -f "${REQUIRED_DEPENDENCIES_JSON_PATH}" ]] && run_a_script "rm ${REQUIRED_DEPENDENCIES_JSON_PATH}"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Detected missing dependencies.  Updating '${PYPROJECT_TOML_PATH}'..."

    # write the updated JSON back to the json file
    run_a_script "tee ${PYPROJECT_JSON_PATH} > /dev/null << SPACEFX_UPDATE_END
${pyproject_json}
SPACEFX_UPDATE_END"

    # Convert the updated JSON back to TOML
    run_a_script "remarshal --input ${PYPROJECT_JSON_PATH} --input-format json --output ${PYPROJECT_TOML_PATH} --output-format toml"

    info_log "...successfully updated '${PYPROJECT_TOML_PATH}' with required dependencies"

    # Cleanup
    [[ -f "${PYPROJECT_JSON_PATH}" ]] && run_a_script "rm ${PYPROJECT_JSON_PATH}"
    [[ -f "${REQUIRED_DEPENDENCIES_JSON_PATH}" ]] && run_a_script "rm ${REQUIRED_DEPENDENCIES_JSON_PATH}"

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

    for i in "${!DEBUG_SHIMS[@]}"; do
        debug_shim=${DEBUG_SHIMS[i]}

        _debug_shim_name="${APP_NAME}"

        # Plugins always use the service as the debugshim name so we
        # can interact as the parent service in the cluster
        [[ ${APP_TYPE} == *"-plugin" ]] && _debug_shim_name="${SVC_IMG}"

        # The first debugshim is the main one; the rest get the suffixes
        if [[ $i -gt 0 ]]; then
            _debug_shim_name="${_debug_shim_name}-${debug_shim}"
        fi

        # Generate the debugshim with the calculated name
        generate_debugshim --debug_shim "${_debug_shim_name}"
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

    debug_log "Generating '${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${debug_shim}.yaml' for '${debug_shim}'..."

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
        --set services.${HELM_SVC_GROUP}.${HELM_SVC_NAME}.hostSourceCodeDir=${HOST_FOLDER}" yaml --disable_log

    run_a_script "tee ${SPACEFX_DIR}/tmp/${APP_NAME}/debugShim_${debug_shim}.yaml > /dev/null << SPACEFX_UPDATE_END
${yaml}
SPACEFX_UPDATE_END" --disable_log


    check_service_account $debug_shim

    if [[ "${SMB_ENABLED_IN_CLUSTER}" == "true" ]]; then
        check_fileserver_creds $debug_shim
    fi


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
    run_a_script "kubectl get serviceaccount -A -o json | jq '.items[] | select(.metadata.name == \"${appName}\" and .metadata.namespace == \"payload-app\") | true'" service_account --disable_log

    debug_log "Service_account: ${service_account}"

    if [[ -z "${service_account}" ]]; then
        debug_log "...not found.  Creating service account '${appName}' in payload-app..."
        run_a_script "kubectl create serviceaccount ${appName} -n payload-app" --disable_log
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


    if [[ "${DEV_PYTHON}" == "true" ]]; then
        info_log "Python detected.  Setting up environment for python development and debug..."
        python_copy_spacesdk_wheel
        python_check_dev_app_dependencies

        debug_log "Triggering poetry to install app dependencies..."
        if [[ "${CLUSTER_ENABLED}" == true ]]; then
            python_poetry_install --no-root --all-extras
        else
            python_poetry_install --no-root --no-spacefx-dev
        fi

        debug_log "...poetry successfully installed app dependencies."

        python_compile_protos

        debug_log "Triggering poetry to install app..."
        if [[ "${CLUSTER_ENABLED}" == true ]]; then
            python_poetry_install --all-extras
        else
            python_poetry_install --no-spacefx-dev
        fi

        debug_log "...poetry successfully installed app."

        # Python Client SDK needs the protos in the right spot
        if [[ "${APP_TYPE}" == "spacesdk-client" ]]; then
            info_log "SpaceSDK-Client detected.  Moving compiled protos to '${CONTAINER_WORKING_DIR:?}/spacefx'..."
            create_directory "${CONTAINER_WORKING_DIR:?}/spacefx"
            run_a_script "rsync -avzh --remove-source-files ${CONTAINER_WORKING_DIR:?}/.protos/spacefx/ ${CONTAINER_WORKING_DIR:?}/spacefx/"
            info_log "...successfully moved compiled protos to '${CONTAINER_WORKING_DIR:?}/spacefx'"
        fi
    fi

    if [[ "${CLUSTER_ENABLED}" == true ]] && [[ "${DEBUG_SHIM_ENABLED}" == true ]]; then

        # Python needs the debugshim image updated with the changes from the python installs above
        if [[ "${DEV_PYTHON}" == "true" ]]; then
            info_log "Committing changes to container for debugshim..."
            run_a_script "docker commit ${CONTAINER_NAME:?} ${CONTAINER_IMAGE:?}:latest"
            info_log "...image updated"
        fi

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