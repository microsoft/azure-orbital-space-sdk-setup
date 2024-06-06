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
source "${MODULE_DIR}/m_30_install_3p_apps.sh"
source "${MODULE_DIR}/m_40_regctl_config.sh"
source "${MODULE_DIR}/m_50_spacefx-config.sh"
source "${MODULE_DIR}/m_60_container_registries.sh"
source "${MODULE_DIR}/m_80_core_registry_hosts.sh"


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
            ;;
    esac
    shift
done


_calculate_for_sudo
_calculate_root_tty
_setup_initial_directories
_script_start
_log_init
_calculate_host_architecture

_install_3p_apps
_generate_spacefx_config_json

_update_regctl_config
_check_for_core_registry_hosts_entry