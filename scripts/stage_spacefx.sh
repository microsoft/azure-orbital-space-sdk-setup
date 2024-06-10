#!/bin/bash
#
# Main entry point to download all dependencies and artifacts to use the Microsoft Azure Orbital Space SDK in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/stage_spacefx.sh [--architecture arm64 | amd64] [--dev-environment]"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../modules/load_modules.sh" $@


############################################################
# Script variables
############################################################
NVIDIA_GPU_PLUGIN=false

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Main entry point to download all dependencies and artifacts to use the Microsoft Azure Orbital Space SDK in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/stage_spacefx.sh [--architecture arm64 | amd64]"
   echo "options:"
   echo "--architecture | -a                [OPTIONAL] Change the target architecture for download (defaults to current architecture)"
   echo "--nvidia-gpu-plugin | -n           [OPTIONAL] Include the nvidia gpu plugin (+325 MB)"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -e|--env) echo "[WARNING] DEPRECATED: this parameter has been deprecated and no longer used.  Please update your scripts accordingly." ;;
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
        --nvidia-gpu-plugin)
            NVIDIA_GPU_PLUGIN=true
            ;;
        -h|--help) show_help ;;
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done

if [[ -z "${ARCHITECTURE}" ]]; then
    case $(uname -m) in
    x86_64) ARCHITECTURE="amd64" ;;
    aarch64) ARCHITECTURE="arm64" ;;
    esac
fi


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log NVIDIA_GPU_PLUGIN

    local extra_args=""

    info_log "Staging third party apps..."
    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_3p_apps.sh --architecture ${ARCHITECTURE}"
    info_log "...successfully staged third party apps"

    info_log "Starting coresvc-registry..."
    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --start"
    info_log "...successfully started coresvc-registry"

    info_log "Staging chart dependencies..."
    extra_args=""
    [[ "${NVIDIA_GPU_PLUGIN}" == true ]] && extra_args="${extra_args} --nvidia-gpu-plugin"
    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_chart_dependencies.sh --architecture ${ARCHITECTURE} ${extra_args}"
    info_log "...successfully staged chart dependencies"


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main