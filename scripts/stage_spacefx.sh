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


############################################################
# Stage core-registry tarball so we can start it up on the k3s side
############################################################
function stage_coresvc_registry(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ -f "${SPACEFX_DIR}/images/${ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar" ]]; then
        info_log "Coresvc-registry already staged to '${SPACEFX_DIR}/images/${ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar'.  Nothing to do."
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    debug_log "Calculating registry repository name..."
    run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" REGISTRY_REPO
    debug_log "...registry repository name calculated as '${REGISTRY_REPO}'"

    info_log "Locating parent registry and calculating tags for '${REGISTRY_REPO}'..."
    calculate_tag_from_channel --tag "${SPACEFX_VERSION}" --result spacefx_version_tag
    find_registry_for_image "${REGISTRY_REPO}:${spacefx_version_tag}" coresvc_registry_parent

    if [[ -z "${coresvc_registry_parent}" ]]; then
        exit_with_error "${REGISTRY_REPO}:${spacefx_version_tag} was not found in any configured containers with pull_enabled.  Please check your access"
    fi

    # We have our parent container registry.  Check to see if it needs a repo suffix
    check_for_repo_prefix --registry "${container_registry}" --repo "${REGISTRY_REPO}" --result _repo_name

    # Check to see if the image is already in docker
    run_a_script "docker images --format '{{json .}}' --no-trunc | jq -r '. | select(.Repository == \"${coresvc_registry_parent}/${_repo_name}\" and .Tag == \"${spacefx_version_tag}\") | any'" has_docker_image --ignore_error

    if [[ "${has_docker_image}" == "true" ]]; then
        info_log "...image ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} already exists in Docker.  Nothing to do"
    else
        info_log "...image ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} not found in Docker.  Pulling..."
        run_a_script "docker pull ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} --platform 'linux/${ARCHITECTURE}'"

        run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" _stage_REGISTRY_REPO
        run_a_script "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" _stage_REGISTRY


        run_a_script "docker tag ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} ${_stage_REGISTRY}/${_stage_REGISTRY_REPO}:${SPACEFX_VERSION}"
        info_log "...successfully pulled ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} to Docker."
    fi

    create_directory "${SPACEFX_DIR}/images/amd64"

    run_a_script "docker save ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} --output ${SPACEFX_DIR}/images/${ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar"


    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log NVIDIA_GPU_PLUGIN

    is_cmd_available "docker" _docker_available

    # shellcheck disable=SC2154
    if [[ "${_docker_available}" == false ]]; then
        exit_with_error "Docker cli is not available and is required for stage_spacefx.sh.  Please install docker and try again."
    fi

    info_log "Staging coresvc-registry..."
    stage_coresvc_registry
    info_log "...successfully staged coresvc-registry"

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


    info_log "Stopping coresvc-registry..."
    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --stop"
    info_log "...successfully stopped coresvc-registry"


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main