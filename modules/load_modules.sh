#!/bin/bash

# Calculate the modules directory
MODULE_DIR=$(dirname "$(realpath "$BASH_SOURCE")")

# Calculate the env directory
ENV_DIR="$(realpath "$(dirname ${MODULE_DIR})")/env"

# Source our ENV file so it's used for all files
source "${ENV_DIR}/spacefx.env"

# Source the modules so we can call them in our scripts
source "${MODULE_DIR}/m_5_run_a_script.sh"
source "${MODULE_DIR}/m_10_is_cmd_available.sh"
source "${MODULE_DIR}/m_15_directories.sh"
source "${MODULE_DIR}/m_20_logging.sh"
source "${MODULE_DIR}/m_25_calculate_host_architecture.sh"
source "${MODULE_DIR}/m_30_install_3p_apps.sh"



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


_calculate_for_sudo
_calculate_root_tty
_setup_initial_directories
_script_start
_log_init
_calculate_host_architecture