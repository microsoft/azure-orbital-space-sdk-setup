#!/bin/bash

############################################################
# Pull the container information
############################################################
function _collect_container_info() {

    # This is only for devcontainers.  Check if we're in a devcontainer and if not, return cleanly
    if [[ -z "${SPACESDK_CONTAINER}" ]]; then
        return
    fi

    if [[ -z "${CONTAINER_ID}" ]]; then
        debug_log "Calculating docker container ID for '${HOSTNAME}'"
        run_a_script "docker ps -q | xargs" _all_container_ids --disable_log
        run_a_script "docker inspect ${_all_container_ids}" _all_container_info  --disable_log
        run_a_script "jq -r '.[] | select(.Config.Hostname == \"${HOSTNAME}\") | .Id'  <<< \${_all_container_info}" CONTAINER_ID  --disable_log

        debug_log "Adding CONTAINER_ID '${CONTAINER_ID}' to ${SPACEFX_DEV_ENV}"
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export CONTAINER_ID=${CONTAINER_ID}
SPACEFX_UPDATE_END" --disable_log
    fi

    create_directory "${SPACEFX_DIR}/tmp/${APP_NAME}"

    # Generate the container info file
    if [[ ! -f "${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json" ]]; then
        run_a_script "docker inspect ${CONTAINER_ID} > ${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json"
    fi

    run_a_script "cat ${SPACEFX_DEV_ENV}" _spacefx_dev_env --disable_log

    # Check and add the HOST_FOLDER to the dev env file
    if [[ "$_spacefx_dev_env" != *"HOST_FOLDER"* ]]; then
        # Workspace mount is always the first mount in a devcontainer
        run_a_script "jq <${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json -r '.[0].HostConfig.Mounts[0].Source'" HOST_FOLDER

        debug_log "Adding HOST_FOLDER '${HOST_FOLDER}' to ${SPACEFX_DEV_ENV}"
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export HOST_FOLDER=${HOST_FOLDER}
SPACEFX_UPDATE_END" --disable_log
    fi

    # Check and add the CONTAINER_IMAGE to the dev env file
    if [[ "$_spacefx_dev_env" != *"CONTAINER_IMAGE"* ]]; then
        run_a_script "jq <${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json -r '.[0].Config.Image'" CONTAINER_IMAGE
        debug_log "Adding CONTAINER_IMAGE '${CONTAINER_IMAGE}' to ${SPACEFX_DEV_ENV}"
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export CONTAINER_IMAGE=${CONTAINER_IMAGE}
SPACEFX_UPDATE_END" --disable_log
    fi


    # Check and add the CONTAINER_NAME to the dev env file
    if [[ "$_spacefx_dev_env" != *"CONTAINER_NAME"* ]]; then
        run_a_script "jq <${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json -r '.[0].Name'" CONTAINER_NAME
        # Remove the first character if its a slash
        if [[ "${CONTAINER_NAME:0:1}" == "/" ]]; then
            CONTAINER_NAME="${CONTAINER_NAME:1}"
        fi
        debug_log "Adding CONTAINER_NAME '${CONTAINER_NAME}' to ${SPACEFX_DEV_ENV}"
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export CONTAINER_NAME=${CONTAINER_NAME}
SPACEFX_UPDATE_END" --disable_log
    fi

    # Check and add the CONTAINER_WORKING_DIR to the dev env file
    if [[ "$_spacefx_dev_env" != *"CONTAINER_WORKING_DIR"* ]]; then
        run_a_script "jq <${SPACEFX_DIR}/tmp/${APP_NAME}/container_info.json -r '.[0].HostConfig.Mounts[] | select(.Source == \"${HOST_FOLDER}\" ) | .Target'" CONTAINER_WORKING_DIR


        debug_log "Adding CONTAINER_WORKING_DIR '${CONTAINER_WORKING_DIR}' to ${SPACEFX_DEV_ENV}"
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export CONTAINER_WORKING_DIR=${CONTAINER_WORKING_DIR}
SPACEFX_UPDATE_END" --disable_log
    fi

    # Check and add the dotnet install dir to the app.env file
    if [[ "$_spacefx_dev_env" != *"DOTNET_INSTALL_DIR"* ]]; then
        run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export DOTNET_INSTALL_DIR=${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/dotnet
SPACEFX_UPDATE_END" --disable_log
        export DOTNET_INSTALL_DIR=${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/dotnet
        export PATH="${CONTAINER_WORKING_DIR:?}/.git/spacefx-dev/dotnet:${PATH}"
    fi




}

############################################################
# Add the app.env to the bashrc so it's always available
############################################################
function _update_bashrc() {

    # This is only for devcontainers.  Check if we're in a devcontainer and if not, return cleanly
    if [[ -z "${SPACESDK_CONTAINER}" ]]; then
        return
    fi

    # Only update .bashrc if it's there
    if [[ ! -f "/root/.bashrc" ]]; then
        return
    fi

    run_a_script "cat /root/.bashrc" _bashrc_contents --disable_log

    # Check and add the HOST_FOLDER to the dev env file
    if [[ "$_bashrc_contents" != *"${SPACEFX_DEV_ENV}"* ]]; then
        debug_log "Adding '${SPACEFX_DEV_ENV}' to /root/.bashrc"
        run_a_script "tee -a /root/.bashrc > /dev/null << SPACEFX_UPDATE_END
source ${SPACEFX_DEV_ENV}
SPACEFX_UPDATE_END" --disable_log
    fi

}

############################################################
# Convert the base64 values to arrays so we can enumerate them
############################################################
function _convert_base64_csv_to_array(){
    local input_string=""
    local -n return_array
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --input)
            shift
            input_string=$1
            ;;
        --result)
            shift
            return_array=$1
            ;;
        esac
        shift
    done

    # Decode the strings from base64
    local decoded_string=$(echo "${input_string}" | base64 -d)

    # Remove the quotes and brackets
    decoded_string=$(echo "${decoded_string}" | sed 's/\[//g; s/\]//g; s/"//g')

    read -r -a return_array <<< "${decoded_string//,/ }"

}

############################################################
# Convert the base64 values to arrays so we can enumerate them
############################################################
function _convert_options_to_arrays(){

    [[ -n "${DOWNLOAD_ARTIFACTS_BASE64}" ]] && _convert_base64_csv_to_array --input "${DOWNLOAD_ARTIFACTS_BASE64}" --result DOWNLOAD_ARTIFACTS
    [[ -n "${PULL_CONTAINERS_BASE64}" ]] && _convert_base64_csv_to_array --input "${PULL_CONTAINERS_BASE64}" --result PULL_CONTAINERS
    [[ -n "${RUN_YAMLS_BASE64}" ]] && _convert_base64_csv_to_array --input "${RUN_YAMLS_BASE64}" --result RUN_YAMLS
    [[ -n "${EXTRA_PACKAGES_BASE64}" ]] && _convert_base64_csv_to_array --input "${EXTRA_PACKAGES_BASE64}" --result EXTRA_PACKAGES
    [[ -n "${ADDL_CONFIG_YAMLS_BASE64}" ]] && _convert_base64_csv_to_array --input "${ADDL_CONFIG_YAMLS_BASE64}" --result ADDL_CONFIG_YAMLS
    [[ -n "${DEBUG_SHIMS_BASE64}" ]] && _convert_base64_csv_to_array --input "${DEBUG_SHIMS_BASE64}" --result DEBUG_SHIMS


}