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
SMB_ENABLED=false
CONTAINERS=()
BUILD_ARTIFACTS=()
DEV_ENVIRONMENT=true # Temporarily setting this to true to unblock work while implementing the build service in parallel
SPACEFX_REGISTRY=""
SPACEFX_REPO_PREFIX=""
SPACEFX_VERSION_TAG=""
SPACEFX_VERSION_BASE_TAG=""
VTH_ENABLED=false

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
   echo "--dev-environment | -d             [OPTIONAL] Setup the environment to support development.  This will enable VTH and downloads full size service container images."
   echo "--vth | -v                         [OPTIONAL] Enable Virtual Test Harness (VTH)."
   echo "--artifact                         [OPTIONAL] Add a build artifact to download and stage.  Must have match in  buildartifacts.json.  Can be passed multiple times"
   echo "--smb                              [OPTIONAL] Enable SMB support in the FileServer component for multi-node clusters."
   echo "--container | -c                   [OPTIONAL] name of the container to pull.  Can be passed multiple times"
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
        --smb)
            SMB_ENABLED=true
            ;;
        -d | --dev-environment)
            DEV_ENVIRONMENT=true
            VTH_ENABLED=true
        ;;
        -v | --vth)
            VTH_ENABLED=true
        ;;
        -c|--container)
            shift
            CONTAINERS+=("$1")
        ;;
        --artifact)
            shift
            BUILD_ARTIFACTS+=("$1")
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
# All the Azure Orbital Space SDK containers are in the same registry.  This speeds up the calculation by eliminating the need to recalculate the registry for each container
############################################################
function calculate_spacefx_registry(){
    info_log "START: ${FUNCNAME[0]}"

    debug_log "Locating parent registry and calculating tags for '${REGISTRY_REPO}'..."
    calculate_tag_from_channel --tag "${SPACEFX_VERSION}" --result SPACEFX_VERSION_TAG
    calculate_tag_from_channel --tag "${SPACEFX_VERSION}_base" --result SPACEFX_VERSION_BASE_TAG
    info_log "SPACEFX_VERSION_TAG calculated as '${SPACEFX_VERSION_TAG}'"
    info_log "SPACEFX_VERSION_BASE_TAG calculated as '${SPACEFX_VERSION_BASE_TAG}'"

    find_registry_for_image "spacesdk-base:${SPACEFX_VERSION_TAG}" SPACEFX_REGISTRY
    info_log "SPACEFX_REGISTRY calculated as '${SPACEFX_REGISTRY}'"

    if [[ -z "${SPACEFX_REGISTRY}" ]]; then
        exit_with_error "Unable to find a registry for 'spacesdk-base:${SPACEFX_VERSION_TAG}'.  Please check that you have the right channel, that you have access to all the container registries in ${SPACEFX_DIR}/config/*.yaml, login to all container registries in ${SPACEFX_DIR}/config/*.yaml (if applicable), and/or update your ${SPACEFX_DIR}/config/*.yaml to include a container registry with spacesdk-base:${SPACEFX_VERSION_TAG}."
    fi

    check_for_repo_prefix_for_registry --registry "${SPACEFX_REGISTRY}" --result SPACEFX_REPO_PREFIX
    info_log "SPACEFX_REPO_PREFIX calculated as '${SPACEFX_REPO_PREFIX}'"

    info_log "SPACEFX_REGISTRY calculated as '${SPACEFX_REGISTRY}'"
    info_log "SPACEFX_VERSION_TAG calculated as '${SPACEFX_VERSION_TAG}'"
    info_log "SPACEFX_REPO_PREFIX calculated as '${SPACEFX_REPO_PREFIX}'"
    write_parameter_to_log SPACEFX_REPO_PREFIX
    write_parameter_to_log SPACEFX_REGISTRY
    write_parameter_to_log SPACEFX_VERSION_TAG
    write_parameter_to_log SPACEFX_VERSION_BASE_TAG

    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Enable FileServer components if user has requested it
############################################################
function enable_fileserver(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${SMB_ENABLED}" == true ]]; then
        info_log "'SMB_ENABLED' = true.  Enabling SMB components..."
        run_a_script "yq eval '(.config.charts[] | select(.group == \"smb\") .enabled) = true' -i \"${SPACEFX_DIR}/config/0_spacesdk-base.yaml\""
        run_a_script "yq eval '.global.fileserverSMB = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""

        info_log "...successfully enabled SMB."
    else
        info_log "'SMB_ENABLED' = false.  Disabling SMB components"
        run_a_script "yq eval '(.config.charts[] | select(.group == \"smb\") .enabled) = false' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        run_a_script "yq eval '.global.fileserverSMB = false' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "...successfully disabled SMB."
    fi


    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Toggle the nvidia GPU setting if requested
############################################################
function toggle_nvidia_gpu(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${NVIDIA_GPU_PLUGIN}" == true ]]; then
        info_log "'NVIDIA_GPU_PLUGIN' = true.  Enabling nVidia GPU in config..."
        run_a_script "yq eval '(.config.charts[] | select(.group == \"nvidia_gpu\") .enabled) = true' -i \"${SPACEFX_DIR}/config/0_spacesdk-base.yaml\""
        info_log "...nVidia GPU successfully enabled."
    else
        info_log "'NVIDIA_GPU_PLUGIN' = false.  Disabling nVidia GPU in config..."
        run_a_script "yq eval '(.config.charts[] | select(.group == \"nvidia_gpu\") .enabled) = false' -i \"${SPACEFX_DIR}/config/0_spacesdk-base.yaml\""
        info_log "...nVidia GPU successfully disabled."
    fi

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Toggle the security restrictions between dev versus prod
############################################################
function toggle_security_restrictions(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${DEV_ENVIRONMENT}" == true ]]; then
        info_log "'DEV_ENVIRONMENT' = true.  Disabling Network Restrictions..."
        run_a_script "yq eval '.global.security.payloadAppNetworkRestrictionsEnabled = false' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "'DEV_ENVIRONMENT' = true.  Disabling Topic Restrictions..."
        run_a_script "yq eval '.global.security.topicRestrictionEnabled = false' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "'DEV_ENVIRONMENT' = true.  Allowing Links to Platform-Deployment..."
        run_a_script "yq eval '(.services.host.link.appConfig[] | select(.name == \"allowLinksToDeploymentSvc\") .value) = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "...security restrictions configured for development"
    else
        info_log "'DEV_ENVIRONMENT' = false.  Enabling Network Restrictions..."
        run_a_script "yq eval '.global.security.payloadAppNetworkRestrictionsEnabled = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""

        info_log "'DEV_ENVIRONMENT' = true.  Enabling Topic Restrictions..."
        run_a_script "yq eval '.global.security.topicRestrictionEnabled = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""

        info_log "'DEV_ENVIRONMENT' = false.  Disabling Links to Platform-Deployment..."
        run_a_script "yq eval '(.services.host.link.appConfig[] | select(.name == \"allowLinksToDeploymentSvc\") .value) = false' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "...Network and Topic restrictions successfully enabled."

        info_log "...security restrictions configured for production"
    fi

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Enable VTH if it's not already enabled
############################################################
function enable_vth(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ "${VTH_ENABLED}" == true ]]; then
        info_log "'VTH_ENABLED' = true.  Enabling VTH..."
        run_a_script "yq eval '.services.platform.vth.prod.enabled = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        run_a_script "yq eval '.services.platform.vth.dev.enabled = true' -i \"${SPACEFX_DIR}/chart/values.yaml\""
        info_log "...successfully enabled VTH."
    else
        info_log "'VTH_ENABLED' = false.  Nothing to do"
    fi


    info_log "FINISHED: ${FUNCNAME[0]}"
}

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

    create_directory "${SPACEFX_DIR}/images/${ARCHITECTURE}"

    debug_log "Calculating registry repository name..."
    run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" REGISTRY_REPO
    debug_log "...registry repository name calculated as '${REGISTRY_REPO}'"

    get_image_name --registry "${SPACEFX_REGISTRY}" --repo "${REGISTRY_REPO}" --result _stage_registry_image_name


    # Check to see if the image is already in docker
    run_a_script "docker images --format '{{json .}}' --no-trunc | jq -r '. | select(.Repository == \"${_stage_registry_image_name}\" and .Tag == \"${SPACEFX_VERSION_TAG}\") | any'" has_docker_image --ignore_error

    if [[ "${has_docker_image}" == "true" ]]; then
        info_log "...image ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} already exists in Docker.  Nothing to do"
    else
        info_log "...image ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} not found in Docker.  Pulling..."
        run_a_script "docker pull ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} --platform 'linux/${ARCHITECTURE}'"

        run_a_script "yq '.services.core.registry.repository' ${SPACEFX_DIR}/chart/values.yaml" _stage_REGISTRY_DEST_REPO
        run_a_script "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" _stage_DEST_REGISTRY


        run_a_script "docker tag ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} ${_stage_DEST_REGISTRY}/${_stage_REGISTRY_DEST_REPO}:${SPACEFX_VERSION}"
        info_log "...successfully pulled ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} to Docker."
    fi

    create_directory "${SPACEFX_DIR}/images/amd64"

    run_a_script "docker save ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG} --output ${SPACEFX_DIR}/images/${ARCHITECTURE}/coresvc-registry_${SPACEFX_VERSION}.tar"

    if [[ "${ARCHITECTURE}" != "${HOST_ARCHITECTURE}" ]]; then
        info_log "Detected cross-architecture staging.  Removing non-platform coresvc-registry image from Docker..."
        run_a_script "docker rmi ${_stage_registry_image_name}:${SPACEFX_VERSION_TAG}" --ignore_error
        run_a_script "docker rmi ${_stage_DEST_REGISTRY}/${_stage_REGISTRY_DEST_REPO}:${SPACEFX_VERSION}" --ignore_error
        info_log "...successfully removed non-platform coresvc-registry image from Docker."
    fi



    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Stage all the service images for a given service group
############################################################
function stage_spacefx_service_images(){
    info_log "START: ${FUNCNAME[0]}"

    local service_group=""
    local stage_container_img_cmd=""

    local enabled_filter="prod.enabled"
    local hasBase_selection="prod.hasBase"

    if [[ "${DEV_ENVIRONMENT}" == true ]]; then
        enabled_filter="dev.enabled"
        hasBase_selection="dev.hasBase"
    fi


    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --service_group)
                shift
                service_group=$1
                ;;
        esac
        shift
    done

    info_log "Staging '${service_group}' spacefx services..."
    run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group} | to_entries[] | select(.value.${enabled_filter} == true) | .key' -r" spacefx_services

    for service in $spacefx_services; do
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.repository' -r" service_repository
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.${hasBase_selection}' -r" service_hasBase --ignore_error

        get_image_name --registry "${SPACEFX_REGISTRY}" --repo "${service_repository}" --result _stage_svc_image_name

        if [[ "${service_hasBase}" == true ]]; then
            info_log "...staging '${service}:${SPACEFX_VERSION_BASE_TAG}'..."
            stage_container_img_cmd="${stage_container_img_cmd} --image ${_stage_svc_image_name}:${SPACEFX_VERSION_BASE_TAG}"
        else
            info_log "...staging '${service}'..."
            stage_container_img_cmd="${stage_container_img_cmd} --image ${_stage_svc_image_name}:${SPACEFX_VERSION_TAG}"
        fi
    done

    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_container_image.sh --architecture ${ARCHITECTURE} ${stage_container_img_cmd}"

    # Update to remove the prefixes on the service images in the registry
    if [[ -n "${SPACEFX_REPO_PREFIX}" ]]; then
        for service in $spacefx_services; do
            local source_repo_name=""
            local dest_repo_name=""
            run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.repository' -r" service_repository
            run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.${hasBase_selection}' -r" service_hasBase --ignore_error

            source_repo_name="registry.spacefx.local/${SPACEFX_REPO_PREFIX}/${service_repository}:${SPACEFX_VERSION_TAG}"
            dest_repo_name="registry.spacefx.local/${service_repository}:${SPACEFX_VERSION}"

            if [[ "${service_hasBase}" == true ]]; then
                source_repo_name="registry.spacefx.local/${SPACEFX_REPO_PREFIX}/${service_repository}:${SPACEFX_VERSION_BASE_TAG}"
                dest_repo_name="registry.spacefx.local/${service_repository}:${SPACEFX_VERSION_BASE_TAG}"
            fi

            info_log "...updating ${source_repo_name} to ${dest_repo_name}..."
            run_a_script "regctl image copy ${source_repo_name} ${dest_repo_name}"
            info_log "...successfully updated ${source_repo_name} to ${dest_repo_name}"
        done
    fi


    info_log "...'${service_group}' spacefx services successfully staged."

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Stage spacefx-base
############################################################
function stage_container_images(){
    info_log "START: ${FUNCNAME[0]}"

    local containers_to_stage=""
    # Regex pattern to match a container registry and image format like "registry/image:tag"
    container_registry_pattern='^[a-zA-Z0-9.-]+\/[a-zA-Z0-9._-]+:[a-zA-Z0-9._-]+$'
    full_image_names=()

    if [[ ${#CONTAINERS[@]} -eq 0 ]]; then
        info_log "...no containers requested.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    for i in "${!CONTAINERS[@]}"; do
        CONTAINER=${CONTAINERS[i]}

        _stage_container_full_image_name=""

        if [[ $CONTAINER =~ $container_registry_pattern ]]; then
            info_log "...'$CONTAINER' is a fully qualified container registry and image string.  Skipping container registry search."
            _stage_container_full_image_name="${CONTAINER}"
        else
            info_log "...'$CONTAINER' is not a fully qualified container registry and image string.  Searching for container registry..."
            find_registry_for_image "${CONTAINER}" _container_registry
            [[ -z "${_container_registry}" ]] && exit_with_error "Unable to find a container registry with container image '${CONTAINER}'.  Please recheck image name, and configured container registries in your config yamls"
            get_image_name --registry "${_container_registry}" --repo "${CONTAINER}" --result _stage_container_full_image_name
            full_image_names+=("${_stage_container_full_image_name}")
        fi

        containers_to_stage="${containers_to_stage} --image ${_stage_container_full_image_name}"
    done

    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_container_image.sh --architecture ${ARCHITECTURE} ${containers_to_stage}"

    # Loop through the images and update the registry to remove the prefix
    for i in "${!full_image_names[@]}"; do
        _full_container_name=${full_image_names[i]}
        _container_registry=${_full_container_name%%/*}

        debug_log "Checking if a prefix exists for '${_container_registry}'..."
        check_for_repo_prefix_for_registry --registry "${_container_registry}" --result _container_registry_repo_prefix

        if [[ -n "${_container_registry_repo_prefix}" ]]; then
            # Remove ${_container_registry}/$_container_registry_repo_prefix from the image name and just have the container name
            _container_repo=${_full_container_name#"${_container_registry}/${_container_registry_repo_prefix}/"}
            info_log "...updating registry.spacefx.local/${_container_registry_repo_prefix}/${_container_repo} to registry.spacefx.local/${_container_repo}..."
            run_a_script "regctl image copy registry.spacefx.local/${_container_registry_repo_prefix}/${_container_repo} registry.spacefx.local/${_container_repo}"
            info_log "...successfully updated registry.spacefx.local/${_container_registry_repo_prefix}/${_container_repo} to registry.spacefx.local/${_container_repo}"
        fi


        if [[ ! $CONTAINER =~ $container_registry_pattern ]]; then
            info_log "...'$CONTAINER' is not a fully qualified container registry and image string.  Searching for container registry..."
            find_registry_for_image "${CONTAINER}" _container_registry
            [[ -z "${_container_registry}" ]] && exit_with_error "Unable to find a container registry with container image '${CONTAINER}'.  Please recheck image name, and configured container registries in your config yamls"
            get_image_name --registry "${_container_registry}" --repo "${CONTAINER}" --result _stage_container_full_image_name
        fi

        containers_to_stage="${containers_to_stage} --image ${_stage_container_full_image_name}"
    done

    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Stage spacefx-base
############################################################
function stage_build_artifacts(){
    info_log "START: ${FUNCNAME[0]}"

    local artifacts_to_stage=""

    if [[ ${#BUILD_ARTIFACTS[@]} -eq 0 ]]; then
        info_log "...no build artifacts requested.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    for i in "${!BUILD_ARTIFACTS[@]}"; do
        artifacts_to_stage="${artifacts_to_stage} --artifact ${BUILD_ARTIFACTS[i]}"
    done

    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_build_artifact.sh --architecture ${ARCHITECTURE} ${artifacts_to_stage}"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log DEV_ENVIRONMENT
    write_parameter_to_log NVIDIA_GPU_PLUGIN
    write_parameter_to_log VTH_ENABLED
    write_parameter_to_log SMB_ENABLED

    for i in "${!CONTAINERS[@]}"; do
        CONTAINER=${CONTAINERS[i]}
        write_parameter_to_log CONTAINER
    done

    for i in "${!BUILD_ARTIFACTS[@]}"; do
        BUILD_ARTIFACT=${BUILD_ARTIFACTS[i]}
        write_parameter_to_log BUILD_ARTIFACT
    done

    is_cmd_available "docker" _docker_available

    # shellcheck disable=SC2154
    if [[ "${_docker_available}" == false ]]; then
        exit_with_error "Docker cli is not available and is required for stage_spacefx.sh.  Please install docker and try again."
    fi

    calculate_spacefx_registry
    toggle_security_restrictions
    toggle_nvidia_gpu
    enable_vth
    enable_fileserver
    _generate_spacefx_config_json

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
    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_chart_dependencies.sh --architecture ${ARCHITECTURE}"
    info_log "...successfully staged chart dependencies"

    info_log "Staging extra container images..."
    stage_container_images
    info_log "...successfully staged extra container images"

    info_log "Staging build artifacts..."
    stage_build_artifacts
    info_log "...successfully staged build artifacts"

    info_log "Staging service images..."
    stage_spacefx_service_images --service_group core
    stage_spacefx_service_images --service_group platform
    stage_spacefx_service_images --service_group host
    info_log "...service images successfully staged."



    info_log "Stopping coresvc-registry..."
    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --stop"
    info_log "...successfully stopped coresvc-registry"


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main