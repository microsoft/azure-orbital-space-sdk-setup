#!/bin/bash

# Calculate the modules directory
MODULE_DIR=$(dirname "$(realpath "$BASH_SOURCE")")

# Calculate the env directory
ENV_DIR="$(realpath "$(dirname ${MODULE_DIR})")/env"

# Source our ENV file so it's used for all files
source "${ENV_DIR}/spacefx.env"

# Source the modules so we can call them in our scripts
source "${MODULE_DIR}/m_5_base.sh"
source "${MODULE_DIR}/m_10_is_cmd_available.sh"
source "${MODULE_DIR}/m_15_directories.sh"
source "${MODULE_DIR}/m_20_logging.sh"
source "${MODULE_DIR}/m_25_calculate_host_architecture.sh"
source "${MODULE_DIR}/m_30_app_prereqs.sh"
source "${MODULE_DIR}/m_40_regctl_config.sh"
source "${MODULE_DIR}/m_45_emulator.sh"
source "${MODULE_DIR}/m_50_spacefx-config.sh"
source "${MODULE_DIR}/m_60_container_registries.sh"
source "${MODULE_DIR}/m_70_certificates.sh"
source "${MODULE_DIR}/m_80_coresvc_registry_hosts.sh"
source "${MODULE_DIR}/m_90_wait_for_deployment.sh"
source "${MODULE_DIR}/m_100_collect_container_info.sh"
source "${MODULE_DIR}/m_110_debugshim.sh"


############################################################
# Common variables used across the modules
############################################################
SCRIPT_NAME=$(basename "$0")
LOG_DIR="${SPACEFX_DIR}/logs"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
LOG_FILE_BASENAME=$(basename "${LOG_FILE}")
RETURN_CODE=""
HOST_ARCHITECTURE=""
ARCHITECTURE=""
RETURN_CODE=""
MAX_WAIT_SECS=300
NEEDS_SUDO=false
ROOT_TTY="/dev/null"
CURRENT_TTY="$(tty)"
INTERNET_CONNECTED=true
APP_INSTALLS=true
DEV_ENVIRONMENT=false

############################################################
# Arguments
# --log_dir: override the precalculated logging directory
# --architecture: change the target architecture for download (defaults to current architecture)
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -a | --architecture)
            shift
            ARCHITECTURE=$1
            ARCHITECTURE=${ARCHITECTURE,,} # Force to lowercase
            if [[ ! "${ARCHITECTURE}" == "amd64" ]] && [[ ! "${ARCHITECTURE}" == "arm64" ]]; then
                echo "--architecture must be 'amd64' or 'arm64'.  '${ARCHITECTURE}' is not valid."
                show_help
                exit 1
            fi
            ;;
        --log_dir)
            shift
            LOG_DIR=$1
            LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
            ;;
        --no_internet)
            shift
            INTERNET_CONNECTED=false
            ;;
        --no_app_installs)
            shift
            APP_INSTALLS=false
            ;;
    esac
    shift
done


_calculate_for_sudo
_calculate_root_tty
_setup_initial_directories
_log_init
_script_start
_calculate_host_architecture

# We can't force the apps to install, so drop out so we don't run any functions that rely on the apps to be present
if [[ "${APP_INSTALLS}" == false ]]; then
    return
fi

_app_prereqs_validate
_generate_spacefx_config_json
_read_environment

# Load the modules and function used by devcontainers
if [[ "${SPACESDK_CONTAINER}" == "true" ]]; then

    _update_regctl_config_devcontainer
    check_and_create_certificate_authority


    if [[ -f "/devfeature/k3s-on-host/k3s.devcontainer.yaml" ]]; then
        run_a_script "mkdir -p $(dirname ${KUBECONFIG})" --disable_log
        run_a_script "cp /devfeature/k3s-on-host/k3s.devcontainer.yaml ${KUBECONFIG}"
    fi

    _check_for_coresvc_registry_hosts_entry_devcontainer
    _collect_container_info
    # _update_bashrc
    _convert_options_to_arrays
    _check_for_python
    _auto_add_downloads

else
# Load modules that are targetted only for the host
    _update_regctl_config_host
    _check_for_coresvc_registry_hosts_entry
fi