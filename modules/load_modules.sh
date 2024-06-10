#!/bin/bash

# Calculate the modules directory
MODULE_DIR=$(dirname "$(realpath "$BASH_SOURCE")")

# Calculate the env directory
ENV_DIR="$(realpath "$(dirname ${MODULE_DIR})")/env"

# Source our ENV file so it's used for all files
source "${ENV_DIR}/spacefx.env"

# Source the modules so we can call them in our scripts
echo "Loading m_5_base.sh"
source "${MODULE_DIR}/m_5_base.sh"
echo "Loading m_10_is_cmd_available.sh"
source "${MODULE_DIR}/m_10_is_cmd_available.sh"
echo "Loading m_15_directories.sh"
source "${MODULE_DIR}/m_15_directories.sh"
echo "Loading m_20_logging.sh"
source "${MODULE_DIR}/m_20_logging.sh"
echo "Loading m_25_calculate_host_architecture.sh"
source "${MODULE_DIR}/m_25_calculate_host_architecture.sh"
echo "Loading m_30_app_prereqs.sh"
source "${MODULE_DIR}/m_30_app_prereqs.sh"
echo "Loading m_40_regctl_config.sh"
source "${MODULE_DIR}/m_40_regctl_config.sh"
echo "Loading m_45_emulator.sh"
source "${MODULE_DIR}/m_45_emulator.sh"
echo "Loading m_50_spacefx-config.sh"
source "${MODULE_DIR}/m_50_spacefx-config.sh"
echo "Loading m_60_container_registries.sh"
source "${MODULE_DIR}/m_60_container_registries.sh"
echo "Loading m_70_certificates.sh"
source "${MODULE_DIR}/m_70_certificates.sh"
echo "Loading m_80_coresvc_registry_hosts.sh"
source "${MODULE_DIR}/m_80_coresvc_registry_hosts.sh"


############################################################
# Common variables used across the modules
############################################################
SCRIPT_NAME=$(basename "$0")
LOG_DIR="${SPACEFX_DIR}/logs"
LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}.log"
RETURN_CODE=""
HOST_ARCHITECTURE=""
ARCHITECTURE=""
RETURN_CODE=""
MAX_WAIT_SECS=300
NEEDS_SUDO=false
ROOT_TTY="/dev/null"
CURRENT_TTY="$(tty)"
INSTALL_APPS=true
INTERNET_CONNECTED=true

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
        --no_app_installs)
            shift
            INSTALL_APPS=false
            ;;
        --no_internet)
            shift
            INTERNET_CONNECTED=false
            ;;
    esac
    shift
done

echo "_calculate_for_sudo"
_calculate_for_sudo
echo "_calculate_root_tty"
_calculate_root_tty
echo "_setup_initial_directories"
_setup_initial_directories
echo "_script_start"
_script_start
echo "_log_init"
_log_init
echo "_calculate_host_architecture"
_calculate_host_architecture

echo "_app_prereqs_validate"
_app_prereqs_validate
echo "_generate_spacefx_config_json"
_generate_spacefx_config_json

echo "_update_regctl_config"
_update_regctl_config
echo "_check_for_coresvc_registry_hosts_entry"
_check_for_coresvc_registry_hosts_entry
