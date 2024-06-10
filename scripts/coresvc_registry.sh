#!/bin/bash
#
# Starts and stops coresvc-registry, which is used during staging, running via k3s, and running in docker.  Will deploy to k3s if available, or fallback to docker
#
# Example Usage:
#
#  "bash ./scripts/coresvc_registry.sh"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../modules/load_modules.sh" $@

############################################################
# Script variables
############################################################
START_REGISTRY=false
STOP_REGISTRY=false
HAS_DOCKER=false
HAS_K3S=false
DESTINATION_HOST=""
REGISTRY_REPO=""

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Starts and stops coresvc-registry, which is used during staging, running via k3s, and running in docker.  Will deploy to k3s if available, or fallback to docker."
   echo
   echo "Syntax: bash ./scripts/coresvc_registry.sh [--dev-environment]"
   echo "options:"
   echo "--start                            [OPTIONAL] Start the registry.  Will be in docker when paired with --dev-environment.  Otherwise will start in kubernetes"
   echo "--stop                             [OPTIONAL] Stops the registry.  Will be in docker when paired with --dev-environment.  Otherwise will stop in kubernetes"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        --start)
            START_REGISTRY=true
        ;;
        --stop)
            STOP_REGISTRY=true
        ;;
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done


############################################################
# Check to make sure we're good to go for the registry in development
############################################################
function check_prerequisites(){
    info_log "START: ${FUNCNAME[0]}"

    is_cmd_available "docker" HAS_DOCKER
    is_cmd_available "kubectl" HAS_K3S

    if [[ "${HAS_K3S}" == true ]]; then
        # if we have kubectl, then check if we have k3s
        is_cmd_available "k3s" HAS_K3S

        if [[ "${HAS_K3S}" == true ]]; then
            # We have k3s, so we need to check if it's running
            run_a_script "pgrep \"k3s\"" k3s_status --ignore_error

            if [[ -z "${k3s_status}" ]]; then
                # k3s is installed but not running
                HAS_K3S=false
            fi
        fi
    fi

    # shellcheck disable=SC2154
    if [[ "${HAS_DOCKER}" == true ]]; then
        debug_log "Docker found."
        DESTINATION_HOST="docker"
    fi

    if [[ "${HAS_K3S}" == true ]]; then
        debug_log "K3s found."
        DESTINATION_HOST="k3s"
    fi

    [[ ! -d "${SPACEFX_DIR}/registry/data" ]] && create_directory "${SPACEFX_DIR}/registry/data"
    [[ ! -d "${SPACEFX_DIR}/certs/registry" ]] && create_directory "${SPACEFX_DIR}/certs/registry"

    debug_log "Calculating registry repository name..."
    run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" REGISTRY_REPO
    debug_log "...registry repository name calculated as '${REGISTRY_REPO}'"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Stop the registry
############################################################
function stop_registry(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${HAS_DOCKER}" == true ]]; then
        info_log "Checking for ${REGISTRY_REPO} in Docker..."
        run_a_script "docker container inspect ${REGISTRY_REPO} | jq '.[0].State.Status' -r" docker_status --ignore_error

        if [[ -n "${docker_status}" ]]; then
            info_log "...found ${REGISTRY_REPO} in Docker.  Stopping..."
            run_a_script "docker remove --force ${REGISTRY_REPO}"
            info_log "...successfully stopped ${REGISTRY_REPO} in Docker"
        else
            info_log "...${REGISTRY_REPO} is not running in Docker.  Nothing to do"
        fi
    fi

    if [[ "${HAS_K3S}" == true ]]; then
        info_log "Checking for ${REGISTRY_REPO} in K3s..."
        #TODO: Add
        # kubectl get pods -l app.kubernetes.io/instance=${REGISTRY_REPO}
    fi

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Start the registry in k3s
############################################################
function start_registry_k3s(){
    info_log "START: ${FUNCNAME[0]}"



    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Start the registry in docker
############################################################
function start_registry_docker(){
    info_log "START: ${FUNCNAME[0]}"

    # Calculate the image tag based on the channel and then check the registries to find it
    info_log "Checking for '${REGISTRY_REPO}' in docker images..."
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
        run_a_script "docker pull ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag}"
        info_log "...successfully pulled ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} to Docker."
    fi


    info_log "Starting '${REGISTRY_REPO}'..."
    run_a_script "docker run -d \
            -p 5000:5000 \
            -v ${SPACEFX_DIR}/registry/data:/var/lib/registry \
            -v ${SPACEFX_DIR}/certs/registry:/certs \
            -e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.spacefx.local.crt \
            -e REGISTRY_HTTP_TLS_KEY=/certs/registry.spacefx.local.key -e \
            --restart=always \
            --name=${REGISTRY_REPO} ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag}"

    info_log "...successfully started core-registry."

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    write_parameter_to_log START_REGISTRY
    write_parameter_to_log STOP_REGISTRY

    check_prerequisites

    stop_registry

    if [[ "${START_REGISTRY}" == false ]]; then
        info_log "------------------------------------------"
        info_log "END: ${SCRIPT_NAME}"
        return
    fi

    write_parameter_to_log DESTINATION_HOST
    info_log "Starting ${REGISTRY_REPO}"

    if [[ ! -f "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.crt" ]]; then
        info_log "Missing certificates detected.  Generating certificates and restarting ${REGISTRY_REPO} (if applicable)"

        generate_certificate --profile "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.ssl.json" --config "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.ssl-config.json" --output "${SPACEFX_DIR}/certs/registry"
    fi

    [[ "${DESTINATION_HOST}" == "docker" ]] && start_registry_docker
    # [[ "${DESTINATION_HOST}" == "k3s" ]] && start_registry_k3s

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main