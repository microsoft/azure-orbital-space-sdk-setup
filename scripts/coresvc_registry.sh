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
IS_RUNNING=false
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
    [[ ! -d "${SPACEFX_DIR}/registry/pypiserver" ]] && create_directory "${SPACEFX_DIR}/registry/pypiserver"
    [[ ! -d "${SPACEFX_DIR}/certs/registry" ]] && create_directory "${SPACEFX_DIR}/certs/registry"


    debug_log "Querying for registry values..."
    run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" REGISTRY_REPO
    run_a_script "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" REGISTRY
    run_a_script "yq '.services.core.registry.serviceNamespace' ${SPACEFX_DIR}/chart/values.yaml" NAMESPACE
    calculate_tag_from_channel --tag "${SPACEFX_VERSION}" --result REGISTRY_TAG

    debug_log "...REGISTRY_REPO calculated as '${REGISTRY_REPO}'"
    debug_log "...REGISTRY calculated as '${REGISTRY}'"
    debug_log "...NAMESPACE calculated as '${NAMESPACE}'"
    debug_log "...REGISTRY_TAG calculated as '${REGISTRY_TAG}'"

    info_log "END: ${FUNCNAME[0]}"
}



############################################################
# Check if the registry is already up and running
############################################################
function check_if_registry_is_already_running(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${HAS_K3S}" == true ]]; then
        info_log "Checking if '${REGISTRY_REPO}' is deployed to K3s..."

        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployments -A -o jsonpath=\"{.items[?(@.metadata.name=='${REGISTRY_REPO}')].metadata.name}\"" _previous_deployment --ignore_error

        if [[ -n "${_previous_deployment}" ]]; then
            info_log "...found '${REGISTRY_REPO}' running in K3s."
            IS_RUNNING=true
        fi
    fi

    # shellcheck disable=SC2154
    if [[ "${HAS_DOCKER}" == true ]]; then
        info_log "Checking if '${REGISTRY_REPO}' is already running in Docker..."

        run_a_script "docker container ls -a --format '{{json .}}' | jq -r 'if any(.Names; .== \"${REGISTRY_REPO}\") then .State else empty end'" container_status --disable_log

        if [[ "${container_status}" == "running" ]]; then
            info_log "...found previous instance of '${REGISTRY_REPO}' in running in Docker"
            IS_RUNNING=true
        else
            # Container status is not empty, but not "running" either.  There's a stopped container that we need to remove
            if [[ -n "${container_status}" ]]; then
                info_log "...found non-running instance of '${REGISTRY_REPO}' in Docker.  Removing..."
                run_a_script "docker container rm ${REGISTRY_REPO} -f"
                info_log "...successfully removed ${REGISTRY_REPO} in Docker"
            fi
        fi
    fi


    info_log "END: ${FUNCNAME[0]}"
}



############################################################
# Stop the registry
############################################################
function stop_registry(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${IS_RUNNING}" == false ]]; then
        info_log "No previous instance of '${REGISTRY_REPO}' found.  Nothing to do"
        return
    fi

    if [[ "${HAS_DOCKER}" == true ]]; then
        info_log "Checking for ${REGISTRY_REPO} in Docker..."
        run_a_script "docker container ls -a --format json | jq '. | select(.Names == \"${REGISTRY_REPO}\")'" docker_container --disable_log

        if [[ -n "${docker_container}" ]]; then
            info_log "...found ${REGISTRY_REPO} in Docker.  Stopping..."
            run_a_script "docker remove --force ${REGISTRY_REPO}"
            info_log "...successfully stopped ${REGISTRY_REPO} in Docker"
        else
            info_log "...${REGISTRY_REPO} is not running in Docker.  Nothing to do"
        fi
    fi

    if [[ "${HAS_K3S}" == true ]]; then
        info_log "Checking for ${REGISTRY_REPO} in K3s..."

        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployments -A -o jsonpath=\"{.items[?(@.metadata.name=='${REGISTRY_REPO}')].metadata.name}\"" _previous_deployment --ignore_error

        if [[ -n "${_previous_deployment}" ]]; then
            info_log "...found '${REGISTRY_REPO}' running in K3s.  Stopping..."
            run_a_script "kubectl --kubeconfig ${KUBECONFIG} delete deployment/${REGISTRY_REPO} -n ${NAMESPACE}"
            info_log "...successfully stopped ${REGISTRY_REPO} in K3s"
        fi
    fi

    run_a_script "lsof -i -P -n | grep LISTEN | grep registry" pid --disable_log --ignore_error

    if [[ -n "${pid}" ]]; then
        pid=$(echo $pid | cut -d ' ' -f 2)
        run_a_script "kill -9 ${pid}"
    fi

    pypiserver_pids=$(ps -aux | grep 'pypiserver' | awk '{print $2}')

    # Kill the Docker container processes
    for pid in $pypiserver_pids; do
        run_a_script "kill -9 $pid" --disable_log --ignore_error
    done

    IS_RUNNING=false

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Start the registry in k3s
############################################################
function start_registry_k3s(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for namespace '${NAMESPACE}'..."

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get namespaces/${NAMESPACE}" has_namespace  --ignore_error

    if [[ -z "${has_namespace}" ]]; then
        info_log "...not found.  Deploying..."
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} create namespace ${NAMESPACE}"
        info_log "...successfully deployed"
    fi

    info_log "Checking if '${REGISTRY_REPO}' container image has been imported..."

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get nodes -o json | jq '.items[0].status.nodeInfo.containerRuntimeVersion' -r" k3sContainerRunTime

    if [[ "${k3sContainerRunTime}" == *"docker"* ]]; then
        # We're running in docker - pull the cache using the docker images command
        run_a_script "docker images" k3s_images_in_cache
    else
        run_a_script "ctr --address /run/k3s/containerd/containerd.sock images list --quiet" k3s_images_in_cache
    fi

    if [[ "${k3s_images_in_cache}" != *"${REGISTRY}/${REGISTRY_REPO}"* ]]; then

        info_log "...'${REGISTRY_REPO}' not found in image cache.  Importing..."

        if [[ ! -f "${SPACEFX_DIR}/images/${HOST_ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar" ]]; then
            exit_with_error "Unable to find '${SPACEFX_DIR}/images/${HOST_ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar'"
        fi

        if [[ "${k3sContainerRunTime}" == *"docker"* ]]; then
            run_a_script "docker load --quiet --input ${SPACEFX_DIR}/images/${HOST_ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar" image_hash

            # Remove the return value we get from docker load
            image_hash=${image_hash#"Loaded image: "}

            # Tag don't match - this'll update it to match what we have in helm
            run_a_script "docker tag ${image_hash} ${REGISTRY}/${REGISTRY_REPO}:${SPACEFX_VERSION}"
        else
            run_a_script "ctr --address /run/k3s/containerd/containerd.sock images import ${SPACEFX_DIR}/images/${HOST_ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar"

            # Tag doesn't match - this'll update it to match what we have in helm
            run_a_script "ctr --address /run/k3s/containerd/containerd.sock images list --quiet | grep '${REGISTRY_REPO}:${REGISTRY_TAG}'" current_tag
            run_a_script "ctr --address /run/k3s/containerd/containerd.sock images tag ${current_tag} ${REGISTRY}/${REGISTRY_REPO}:${SPACEFX_VERSION}"
        fi

    fi

    # Run a helm dependency update so we can
    if [[ ! -f "${SPACEFX_DIR}/chart/Chart.lock" ]]; then
        run_a_script "helm --kubeconfig ${KUBECONFIG} dependency update ${SPACEFX_DIR}/chart"
    fi

    run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart --set services.core.registry.enabled=true" registry_yaml

    debug_log "...deploying core-registry..."
    run_a_script "kubectl --kubeconfig ${KUBECONFIG} apply -f - <<SPACEFX_UPDATE_END
${registry_yaml}
SPACEFX_UPDATE_END" --disable_log

    wait_for_deployment --namespace "${NAMESPACE}" --deployment "${REGISTRY_REPO}"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Start the registry in docker
############################################################
function start_registry_docker(){
    info_log "START: ${FUNCNAME[0]}"

    # Calculate the image tag based on the channel and then check the registries to find it
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
        run_a_script "docker pull ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag}"
        info_log "...successfully pulled ${coresvc_registry_parent}/${_repo_name}:${spacefx_version_tag} to Docker."
    fi

    info_log "Starting '${REGISTRY_REPO}'..."
    run_a_script "docker run -d \
            -p 5000:5000 \
            -p 8080:8080 \
            -v ${SPACEFX_DIR}/registry/data:/var/lib/registry \
            -v ${SPACEFX_DIR}/certs/registry:/certs \
            -v ${SPACEFX_DIR}/registry/pypiserver:/data/packages \
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
    check_if_registry_is_already_running

    if [[ "${STOP_REGISTRY}" == true ]]; then
        stop_registry
        info_log "------------------------------------------"
        info_log "END: ${SCRIPT_NAME}"
        return
    fi

    if [[ "${START_REGISTRY}" == true ]]; then
        write_parameter_to_log DESTINATION_HOST
        info_log "Starting ${REGISTRY_REPO}"

        if [[ ! -f "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.crt" ]]; then
            info_log "Missing certificates detected.  Generating certificates and restarting ${REGISTRY_REPO} (if applicable)"
            # We have to stop the registry if we have to regen the certificates
            stop_registry

            # Generate the new certificates for SSL/TLS
            generate_certificate --profile "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.ssl.json" --config "${SPACEFX_DIR}/certs/registry/registry.spacefx.local.ssl-config.json" --output "${SPACEFX_DIR}/certs/registry"
        fi

        if [[ "${IS_RUNNING}" == true ]]; then
            info_log "Registry is already running.  Nothing to do"
        else
            [[ "${DESTINATION_HOST}" == "docker" ]] && start_registry_docker
            [[ "${DESTINATION_HOST}" == "k3s" ]] && start_registry_k3s
        fi

        info_log "------------------------------------------"
        info_log "END: ${SCRIPT_NAME}"
    fi


}


main
