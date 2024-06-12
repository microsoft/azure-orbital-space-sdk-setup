#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/devcontainer-feature-k3s/README.md

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi
SPACEFX_DEV_ENV="${SPACEFX_DEV_ENV:-"/spacefx-dev/app.env"}"
SPACEFX_DIR="${SPACEFX_DIR:-"/var/spacedev"}"
CLUSTER_ENABLED="${CLUSTER_ENABLED:-"true"}"
HOST_INTERFACE_CONTAINER="host_interface"
HOST_INTERFACE_CONTAINER_BASE="mcr.microsoft.com/devcontainers/base:ubuntu22.04"
APP_NAME="${APP_NAME:-"na"}"
APP_TYPE="${APP_TYPE:-"payloadapp"}"
APP_TYPE=${APP_TYPE,,}  # Force to lowercase
ADDL_DEBUG_SHIM_SUFFIXES="${ADDL_DEBUG_SHIM_SUFFIXES:-""}"
SPACESDK_CONTAINER="${SPACESDK_CONTAINER:-"false"}"

ADDL_DEBUG_SHIM_SUFFIXES="${ADDL_DEBUG_SHIM_SUFFIXES:-""}"
ADDL_DEBUG_SHIM_SUFFIXES=${ADDL_DEBUG_SHIM_SUFFIXES,,} # Force to lowercase
DEBUG_SHIMS="${APP_NAME}"

if [[ -n "${ADDL_DEBUG_SHIM_SUFFIXES}" ]]; then
    DEBUG_SHIMS="${DEBUG_SHIMS},${ADDL_DEBUG_SHIM_SUFFIXES}"
fi

DEBUG_SHIM_ENABLED="${DEBUG_SHIM_ENABLED:-"true"}"
DEBUG_SHIM_PRE_YAML_FILE="${DEBUG_SHIM_PRE_YAML_FILE:-""}"
DEBUG_SHIM_POST_YAML_FILE="${DEBUG_SHIM_POST_YAML_FILE:-""}"

DOWNLOAD_ARTIFACTS="${DOWNLOAD_ARTIFACTS:-""}"
PULL_CONTAINERS="${PULL_CONTAINERS:-""}"
RUN_YAMLS="${RUN_YAMLS:-""}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-""}"
ADDL_CONFIG_YAMLS="${ADDL_CONFIG_YAMLS:-""}"



SVC_IMG="payloadapp"
SVC_GROUP="payloadapp"

LOG_LEVEL="${LOG_LEVEL:-"DEBUG"}"
LOG_LEVEL=${LOG_LEVEL^^} # Force to uppercase

SPACEFX_VERSION_LATEST="0.11.0"

ALLOWED_APP_TYPES=("none"
                    "sdk-service"
                    "payloadapp"
                    "hostsvc-sensor-plugin"
                    "hostsvc-logging-plugin"
                    "hostsvc-link-plugin"
                    "hostsvc-position-plugin"
                    "platform-mts-plugin"
                    "platform-deployment-plugin"
                    "vth-plugin"
                    "sdk"
                    "spacesdk-core")

ALLOWED_LOG_LEVELS=("ERROR"
                    "WARN"
                    "INFO"
                    "DEBUG"
                    "TRACE")


# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

set -e

# Clean up
rm -rf /var/lib/apt/lists/*


# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

# Source /etc/os-release to get OS info
. /etc/os-release


############################################################
# Convert a variable to a base64 encoded string
############################################################
function base64_encode_variable() {
    local varToEncode=$1

    local returnResult=""
    returnResult=$(eval "echo \$${varToEncode}")

    # Trim the values by removing whitespace before and after the values
    returnResult=$(echo $returnResult | sed 's/ *, */,/g')

    # Add an extra set of quotes to make the array correct
    returnResult="\"${returnResult}\""

    # Replace the commas with quotes-comma-quotes
    returnResult=$(echo "[$returnResult]" | sed 's/,/","/g')

    # encode to base64
    returnResult=$(echo $returnResult | base64 -w 0)

    eval $varToEncode="'$returnResult'"

}

############################################################
# Build the spacefx-dev directory and copy any files that'll be used while running the container
############################################################
function build_dest_directory() {

    echo "Creating /spacefx-dev directory..."
    mkdir -p "/spacefx-dev"

    echo "Copying scripts to /spacefx-dev/..."
    cp ./*.sh /spacefx-dev/
    cp ./azure-orbital-space-sdk-setup /azure-orbital-space-sdk-setup/ -r


    while read -r shellFile; do
        chmod +x "${shellFile}"
        chmod 777 "${shellFile}"
    done < <(find "/spacefx-dev" -iname "*.sh")

    echo "Updating /devfeature/k3s-on-host/.env file with CLUSTER_ENABLED=${CLUSTER_ENABLED}..."
    mkdir -p /devfeature/k3s-on-host
    tee /devfeature/k3s-on-host/.env -a > /dev/null << UPDATE_END
export CLUSTER_ENABLED=${CLUSTER_ENABLED}
UPDATE_END
    echo "...Successfully updated /devfeature/k3s-on-host/.env file."

}

############################################################
# Validate the options that are passed are valid
############################################################
function validate_options(){
    # Got a bad app type
    if [[ ! " ${ALLOWED_APP_TYPES[*]} " =~ " ${APP_TYPE} " ]]; then
        echo "[ERROR]: app_type '${APP_TYPE}' is invalid.  Valid options are: '${ALLOWED_APP_TYPES[*]}'"
        return 1
    fi

    # Got a bad log level
    if [[ ! " ${ALLOWED_LOG_LEVELS[*]} " =~ " ${LOG_LEVEL} " ]]; then
        echo "[ERROR]: app_type '${LOG_LEVEL}' is invalid.  Valid options are: '${ALLOWED_LOG_LEVELS[*]}'"
        return 1
    fi

    # we only mount /var so we have to make sure spacefx_dir is on /var
    if [[ $SPACEFX_DIR != "/var"* ]]; then
        echo "[ERROR]: SPACEFX_DIR of '${SPACEFX_DIR}' is not supported.  SPACEFX_DIR must start with '/var' in development.  Please update your SPACEFX_DIR parameter in your devcontainer.json and rebuild"
        return 1
    fi

    # app name is missing
    if [[ "${APP_NAME}" == "na" ]]; then
        echo "[ERROR]: app_name is a required parameter.  Please update your devcontainer.json and include '\"app_name\": \"my-payload-app\"'"
        return 1
    fi

    if [[ "${SPACEFX_VERSION}" == "latest" ]]; then
        echo "[INFO]: Updating SPACEFX_VERSION from 'latest' to '${SPACEFX_VERSION_LATEST}'"
        SPACEFX_VERSION="${SPACEFX_VERSION_LATEST}"
    fi

    if [[ $APP_TYPE == *-plugin ]]; then
        # Found a plugin for an spacefx service.  Update accordingly
        SVC_IMG=${APP_TYPE%-plugin}
    fi

    if [[ $APP_TYPE == "sdk-service" ]]; then
        # We're debugging a spacefx service
        SVC_IMG=${APP_NAME}
    fi

    case $(uname -m) in
        x86_64) ARCHITECTURE="amd64" ;;
        aarch64) ARCHITECTURE="arm64" ;;
    esac

    # Calculate what local host spacedev dir pointer is by replacing the first forward slash with '/host_'
    # i.e. /var/spacedev becomes /host_var/spacedev
    # i.e. /tmp/folder becomes /host_tmp/folder
    # but we're forcing it to be off /var so we can mount it in our devcontainer feature
    SPACEFX_DIR_FOR_HOST="${SPACEFX_DIR/\//\/host_}"
}

############################################################
# Update SPACEFX_ENV with the SPACEFX_DIR and LOG_LEVEL files
############################################################
function update_spacefx_env() {
    # Remove the values from the spacefx.env file
    sed -i '/^SPACEFX_DIR/d' ./azure-orbital-space-sdk-setup/env/spacefx.env
    sed -i '/^LOG_LEVEL/d' ./azure-orbital-space-sdk-setup/env/spacefx.env

    # Add the values to the spacefx.env file
    echo "SPACEFX_DIR=${SPACEFX_DIR}" >> ./azure-orbital-space-sdk-setup/env/spacefx.env
    echo "LOG_LEVEL=${LOG_LEVEL}" >> ./azure-orbital-space-sdk-setup/env/spacefx.env

}


############################################################
# Generate the app.env file
############################################################
function gen_app_env() {

    # Base64 encode the options so we can pass them later on
    [[ -n "${DOWNLOAD_ARTIFACTS}" ]] && base64_encode_variable DOWNLOAD_ARTIFACTS
    [[ -n "${PULL_CONTAINERS}" ]] && base64_encode_variable PULL_CONTAINERS
    [[ -n "${RUN_YAMLS}" ]] && base64_encode_variable RUN_YAMLS
    [[ -n "${EXTRA_PACKAGES}" ]] && base64_encode_variable EXTRA_PACKAGES
    [[ -n "${ADDL_CONFIG_YAMLS}" ]] && base64_encode_variable ADDL_CONFIG_YAMLS
    [[ -n "${DEBUG_SHIMS}" ]] && base64_encode_variable DEBUG_SHIMS

    echo "Creating ${SPACEFX_DEV_ENV:?} file..."
    tee "${SPACEFX_DEV_ENV:?}" -a > /dev/null << UPDATE_END
export _REMOTE_USER=${_REMOTE_USER}
export _REMOTE_USER_HOME=${_REMOTE_USER_HOME}
export _CONTAINER_USER=${_CONTAINER_USER}
export CLUSTER_ENABLED=${CLUSTER_ENABLED}
export K3S_VERSION=${K3S_VERSION}
export ARCHITECTURE=${ARCHITECTURE}
export HOST_INTERFACE_CONTAINER=${HOST_INTERFACE_CONTAINER}
export HOST_INTERFACE_CONTAINER_BASE=${HOST_INTERFACE_CONTAINER_BASE}
export SPACEFX_DIR=${SPACEFX_DIR}
export SPACEFX_DIR_FOR_HOST=${SPACEFX_DIR_FOR_HOST}
export SPACESDK_CONTAINER=${SPACESDK_CONTAINER}
export APP_NAME=${APP_NAME}
export APP_TYPE=${APP_TYPE}
export DEBUG_SHIM_PRE_YAML_FILE=${DEBUG_SHIM_PRE_YAML_FILE}
export DEBUG_SHIM_POST_YAML_FILE=${DEBUG_SHIM_POST_YAML_FILE}
export DEBUG_SHIMS_BASE64=${DEBUG_SHIMS}
export DEBUG_SHIM_ENABLED=${DEBUG_SHIM_ENABLED}
export DOWNLOAD_ARTIFACTS_BASE64=${DOWNLOAD_ARTIFACTS}
export PULL_CONTAINERS_BASE64=${PULL_CONTAINERS}
export RUN_YAMLS_BASE64=${RUN_YAMLS}
export EXTRA_PACKAGES_BASE64=${EXTRA_PACKAGES}
export ADDL_CONFIG_YAMLS_BASE64=${ADDL_CONFIG_YAMLS}
UPDATE_END

}


############################################################
# Generate the config files that are read by apps and scripts that can't use the app.env file
############################################################
function gen_config_files() {
    mkdir -p "/spacefx-dev/config"
    echo "${DEV_LANGUAGE}" > /spacefx-dev/config/dev_language
    echo "${DOTNET_SDK_VERSION}" > /spacefx-dev/config/dotnet_sdk_version
    echo "${SPACEFX_VERSION}" > /spacefx-dev/config/spacefx_version
    echo "${APP_NAME}" > /spacefx-dev/config/app_name
    echo "${APP_TYPE}" > /spacefx-dev/config/app_type
}


function main() {
    validate_options
    update_spacefx_env
    build_dest_directory
    gen_app_env
    gen_config_files
}


main
set +e