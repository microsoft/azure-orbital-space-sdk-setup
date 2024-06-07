#!/bin/bash
#
#  Builds a generic container image with a dynamic docker file supplied by the repo directory.
#
# arguments:
#
#   image_tag - The image tag used for generation.  Will have the processor architecture suffix
#   architecture - processor architecture - either arm64 or amd64
#   repo_dir - The path to the root of the repo
#   dockerFile - The relative path to the docker file used
#   app_name - The name of the app we're building.  Will be used in the naming of the final image
#
#
# Example Usage:
#
#  "bash /var/spacedev/build/build_containerImage.sh --dockerfile Dockerfiles/Dockerfile --image-tag 0.0.1 --architecture arm64 --repo-dir ~/repos/project_source_code"

source $(dirname $(realpath "$0"))/../modules/load_modules.sh $@


############################################################
# Script variables
############################################################
APP_NAME=""
DOCKERFILE=""
IMAGE_TAG=""
REPO_DIR=""
BUILD_ARGS=""
EXTRA_PKGS=""
ANNOTATION_CONFIG=""
BUILDDATE_VALUE=$(date -u +'%Y%m%dT%H%M%S')

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Builds a generic container image with a dynamic docker file supplied by the repo directory."
   echo
   echo "Syntax: bash /var/spacedev/build/build_containerImage.sh --dockerfile Dockerfiles/Dockerfile --image-tag 0.0.1 --architecture arm64 --repo-dir ~/repos/project_source_code"
   echo "options:"
   echo "--architecture | -a                [REQUIRED] The processor architecture for the final build.  Must be either arm64 or amd64"
   echo "--app-name | -n                    [REQUIRED] The name of the app to build - this will be the name of the image that's generated"
   echo "--image-tag | -t                   [REQUIRED] The image tag for the final container image.  Will be suffixed with the processor architecture.  (i.e. 0.0.1_arm64)."
   echo "--repo-dir | -r                    [REQUIRED] Local root directory of the repo (will have a subdirectory called '.devcontainer')"
   echo "--dockerfile | -d                  [REQUIRED] Relative path to the docker file within repo-dir"
   echo "--annotation-config                [OPTIONAL] Filename of the annotation configuration to add to spacefx-config.json.  File must reside within ${SPACEFX_DIR}/config/github/annotations"
   echo "--build-arg | -b                   [OPTIONAL] Individual name/value pairs to pass as build arguments to the docker build command.  Once key-value-pair per build_arg like --build-arg key=value"
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
        --annotation-config)
            shift
            ANNOTATION_CONFIG=$1
            if [[ ! -f "${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG}" ]]; then
                echo "Annotation configuration file '${ANNOTATION_CONFIG}' not found in '${SPACEFX_DIR}/config/github/annotations'"
                show_help
            fi
        ;;
        -b|--build-arg)
            shift
            BUILD_ARGS="${BUILD_ARGS} --build-arg ${1}"
            ;;
        -n|--app-name)
            shift
            # Force to lowercase
            APP_NAME=${1,,}
            ;;
        -d|--dockerfile)
            shift
            DOCKERFILE=$1
            ;;
        -a|--architecture)
            shift
            ARCHITECTURE=$1
            ARCHITECTURE=${ARCHITECTURE,,}
            if [[ ! "${ARCHITECTURE}" == "amd64" ]] && [[ ! "${ARCHITECTURE}" == "arm64" ]]; then
                echo "--architecture must be 'amd64' or 'arm64'.  '${ARCHITECTURE}' is not valid."
                show_help
            fi
            ;;
        -t|--image-tag)
            shift
            IMAGE_TAG=$1
            # Force to lowercase
            IMAGE_TAG="${IMAGE_TAG,,}"
            ;;
        -r|--repo-dir)
            shift
            REPO_DIR=$1
            # Removing the trailing slash if there is one
            REPO_DIR=${REPO_DIR%/}
            ;;
        *) echo "Unknown parameter passed: $1"; show_help ;;
    esac
    shift
done


check_for_cmd --app "docker" --documentation-url "https://docs.docker.com/engine/install/ubuntu/"
check_for_cmd --app "devcontainer" --documentation-url "https://code.visualstudio.com/docs/devcontainers/devcontainer-cli"


############################################################
# Update DevContainer.json config
############################################################
function update_devcontainer_json(){
    info_log "START: ${FUNCNAME[0]}"

    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR}" devcontainer_json --disable_log

    echo "${devcontainer_json}"

    # update the parameters so we don't build the cluster
    run_a_script "jq '.configuration.features |= with_entries(select(.key | contains(\"spacefx-dev\")) | .value += {\"cluster_enabled\": \"false\"})' <<< \${devcontainer_json}" devcontainer_json --disable_log

    # update the parameters so that we only build in /var/spacedev
    run_a_script "jq '.configuration.features |= with_entries(select(.key | contains(\"spacefx-dev\")) | .value += {\"spacefx_dir\": \"${SPACEFX_DIR}\"})' <<< \${devcontainer_json}" devcontainer_json --disable_log
    [[ -z "${devcontainer_json}" ]] && exit_with_error "Failed to query devcontainer_json (received empty results).  Please check the logs for more information."

    # update the devcontainer user to be root
    run_a_script "jq '.configuration += {\"remoteUser\": \"root\"}' <<< \${devcontainer_json}" devcontainer_json --disable_log
    run_a_script "jq '.configuration += {\"containerUser\": \"root\"}' <<< \${devcontainer_json}" devcontainer_json --disable_log

    # Remove the extra configFilePath that gets added by devcontainer cli
    run_a_script "jq 'del(.configuration.configFilePath)' <<< \${devcontainer_json}" devcontainer_json --disable_log
    run_a_script "jq '.configuration' <<< \${devcontainer_json}" devcontainer_json --disable_log

    run_a_script "mkdir -p ${SPACEFX_DIR}/tmp/${APP_NAME}" --disable_log

    run_a_script "tee ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json > /dev/null << SPACEFX_UPDATE_END
${devcontainer_json}
SPACEFX_UPDATE_END" --disable_log


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Stand up and start the devcontainer
############################################################
function provision_devcontainer(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for previously running devcontainer"
    run_a_script "docker ps -q --filter \"label=devcontainer.local_folder=${REPO_DIR}\" --filter \"name=${APP_NAME}\"" previous_containers --ignore_error
    if [[ -n "${previous_containers}" ]]; then
        for container in $previous_containers; do
            info_log "Removing previous container '${container}'..."
            run_a_script "docker container rm -f ${container}"
            info_log "...previous container removed"
        done
    fi

    info_log "Building the devcontainer..."
    run_a_script "devcontainer build --workspace-folder ${REPO_DIR} --no-cache --platform linux/${ARCHITECTURE} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json"
    run_a_script "devcontainer up --workspace-folder ${REPO_DIR} --remove-existing-container --workspace-mount-consistency cached --id-label devcontainer.local_folder=${REPO_DIR} --id-label devcontainer.config_file=${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json --log-level debug --log-format json --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json --default-user-env-probe loginInteractiveShell --build-no-cache --remove-existing-container --mount type=volume,source=vscode,target=/vscode,external=true --update-remote-user-uid-default on --mount-workspace-git-root true"

    info_log "Devcontainer built"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Query the devcontainer for our variables
############################################################
function gather_devcontainer_values(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Calculating container ID..."
    run_a_script "docker ps -q --filter \"label=devcontainer.local_folder=${REPO_DIR}\"" CONTAINER_ID
    info_log "...container id calculated as '${CONTAINER_ID}'"

    info_log "Calculating container workspace folder..."
    run_a_script "docker inspect ${CONTAINER_ID} | jq -r '.[0].Mounts[] | select(.Source == \"${REPO_DIR}\") | .Destination'" CONTAINER_WORKSPACE_FOLDER
    info_log "Container workspace folder calculated as '${CONTAINER_WORKSPACE_FOLDER}'"

    info_log "Calculating image name..."
    run_a_script "docker inspect ${CONTAINER_ID} | jq -r '.[0].Config.Image'" CONTAINER_IMAGE
    info_log "Container image name calculated as '${CONTAINER_IMAGE}'"

    # Query to get the base image
    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR}" devcontainer_json
    run_a_script "jq -r '.configuration.image' <<< \${devcontainer_json}" DEV_CONTAINER_BASE_IMAGE

    # Query if there's extra packages to apt-get install against
    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} | jq '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | true'" has_spacefx_feature --ignore_error

    if [[ -n ${has_spacefx_feature} ]]; then
        run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} | jq -r '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | .value.extra_packages'" extra_packages --ignore_error

        if [[ -n "${extra_packages}" ]]; then
            info_log "Extra packages detected in spacefx-dev container feature (${extra_packages}).  Adding them to container image"
            EXTRA_PKGS="${extra_packages//,/ }"
        fi
    fi

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Take the resources from the devcontainer and use them to build a production container
############################################################
function build_prod_image_container(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Building ${APP_NAME}:${ARCHITECTURE} container..."

    info_log "Building service container base for '${APP_NAME}'"
    local fullTagCmd=""

    local buildArgs="${BUILD_ARGS} "
    [[ -n "${DEV_CONTAINER_BASE_IMAGE}" ]] && buildArgs+="--build-arg DEV_CONTAINER_BASE_IMG=\"${DEV_CONTAINER_BASE_IMAGE}\" "

    [[ -n "${EXTRA_PKGS}" ]] && buildArgs+="--build-arg EXTRA_PKGS=\"${EXTRA_PKGS}\" "

    info_log "...adding tag '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}'";
    fullTagCmd+=" --tag ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}"

    info_log "...adding tag '${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}'";
    fullTagCmd+=" --tag ${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}"

    info_log "...adding tag '${DEST_CONTAINER_REGISTRY}/:${IMAGE_TAG}'";
    fullTagCmd+=" --tag ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}"

    info_log "...adding tag '${DEST_REPO}:${IMAGE_TAG}'";
    fullTagCmd+=" --tag ${DEST_REPO}:${IMAGE_TAG}"

    buildArgs+="--build-arg APP_NAME=\"${APP_NAME}\" "
    labelArgs="--label \"org.app_name=${APP_NAME}\" "

    buildArgs+="--build-arg CONTAINER_REGISTRY=\"${DEST_CONTAINER_REGISTRY}\" "

    buildArgs+="--build-arg APP_VERSION=\"${IMAGE_TAG}\" "
    labelArgs+="--label \"org.spacefx.app_version=${IMAGE_TAG}\" "

    buildArgs+="--build-arg SPACEFX_VERSION=\"${SPACEFX_VERSION}\" "
    buildArgs+="--build-arg SDK_VERSION=\"${SPACEFX_VERSION}\" "
    labelArgs+="--label \"org.spacefx.spacefx_version=${SPACEFX_VERSION}\" "

    labelArgs+="--label \"org.spacefx.app_builddate=${BUILDDATE_VALUE}\" "

    buildArgs+="--build-arg ARCHITECTURE=\"${ARCHITECTURE}\" "
    labelArgs+="--label \"org.architecture=${ARCHITECTURE}\" "

    dockerPath=""
    if [[ $DOCKERFILE = /* ]]; then
        dockerPath="${DOCKERFILE}"
    else
        dockerPath="${REPO_DIR}/${DOCKERFILE}"
    fi

    run_a_script "docker build \
                ${buildArgs} \
                ${labelArgs} \
                ${fullTagCmd} \
                --progress plain \
                --file \"${dockerPath}\" \"${REPO_DIR}\""

    info_log "...successfully built ${DEST_REPO}:${ARCHITECTURE} container"



    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Be a good script-citizen and clean up after ourselves
############################################################
cleanup(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Resetting 'DOCKER_DEFAULT_PLATFORM' to 'linux/${HOST_ARCHITECTURE}'..."
    export DOCKER_DEFAULT_PLATFORM="linux/${HOST_ARCHITECTURE}"
    info_log "...successfully reset 'DOCKER_DEFAULT_PLATFORM' to 'linux/${HOST_ARCHITECTURE}'."

    info_log "END: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log APP_NAME
    write_parameter_to_log DOCKERFILE
    write_parameter_to_log REPO_DIR
    write_parameter_to_log BUILD_ARGS

    if [[ -n "${ANNOTATION_CONFIG}" ]]; then
        write_parameter_to_log GITHUB_ANNOTATION
        run_a_script "cp ${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG} ${SPACEFX_DIR}/config/${ANNOTATION_CONFIG}" --disable_log
        _generate_spacefx_config_json
    fi


    get_registry_with_push_access DEST_CONTAINER_REGISTRY
    write_parameter_to_log DEST_CONTAINER_REGISTRY

    if [[ -z "${DEST_CONTAINER_REGISTRY}" ]]; then
        exit_with_error "No container registries are configured for push.  Unable to deploy container image and manifest"
    fi

    DEST_SPACEFX_TAG="${SPACEFX_VERSION}"

    # Check if we have a tag suffix from our config file
    run_a_script "jq -r 'if (.config | has(\"tagSuffix\")) then .config.tagSuffix else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" tag_suffix --disable_log

    if [[ -n "${tag_suffix}" ]]; then
        IMAGE_TAG="${IMAGE_TAG}${tag_suffix}"
        DEST_SPACEFX_TAG="${SPACEFX_VERSION}${tag_suffix}"
    fi

    write_parameter_to_log IMAGE_TAG
    write_parameter_to_log DEST_SPACEFX_TAG

    # Check if our destination repo has a repositoryPrefix
    run_a_script "jq -r '.config.containerRegistries[] | select(.url == \"${DEST_CONTAINER_REGISTRY}\") | if (has(\"repositoryPrefix\")) then .repositoryPrefix else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" REPO_PREFIX

    DEST_REPO="${APP_NAME}"

    if [[ -n "${REPO_PREFIX}" ]]; then
        info_log "Repository Prefix found for ${DEST_CONTAINER_REGISTRY}.  Prefixing with '${REPO_PREFIX}'"
        DEST_REPO="${REPO_PREFIX}/${DEST_REPO}"
    fi

    write_parameter_to_log DEST_REPO

    provision_emulator


    if [[ -f "${REPO_DIR}/.devcontainer/devcontainer.json" ]]; then
        info_log "Checking for spacefx-dev..."
        run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} | jq '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | true'" has_spacefx_feature --ignore_error
        info_log "Result: ${has_spacefx_feature}"

        if [[ -n ${has_spacefx_feature} ]]; then
            # pull_conifg_yamls_and_regen_spacefx --repo-dir ${REPO_DIR}
            update_devcontainer_json
            provision_devcontainer
            gather_devcontainer_values
        fi
    fi


    build_prod_image_container
    push_to_repository --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}"
    gen_and_push_manifest --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}"

    set_annotation_to_image --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}" \
                            --annotation "org.spacefx.item_type=containerimage" \
                            --annotation "org.spacefx.app_name=${APP_NAME}" \
                            --annotation "org.spacefx.spacefx_version=${SPACEFX_VERSION}"

    add_redirect_to_image   --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}" \
                            --destination_image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}" \
                            --annotation "org.spacefx.item_type=containerimage" \
                            --annotation "org.spacefx.app_name=${APP_NAME}" \
                            --annotation "org.spacefx.app_name=${APP_NAME}" \
                            --annotation "org.spacefx.app_version=${APP_VERSION}" \
                            --annotation "org.spacefx.spacefx_version=${SPACEFX_VERSION}" \
                            --annotation "org.architecture=${ARCHITECTURE}" \
                            --annotation "org.spacefx.app_builddate=${BUILDDATE_VALUE}"

    # Only push if we're using a different app_version that spacefx
    if [[ "${IMAGE_TAG}" != "${DEST_SPACEFX_TAG}" ]]; then
        gen_and_push_manifest --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}"

        set_annotation_to_image --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}" \
                                --annotation "org.spacefx.item_type=containerimage" \
                                --annotation "org.spacefx.app_name=${APP_NAME}" \
                                --annotation "org.spacefx.spacefx_version=${SPACEFX_VERSION}"


        add_redirect_to_image   --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}" \
                                --destination_image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${IMAGE_TAG}_${ARCHITECTURE}" \
                                --annotation "org.spacefx.item_type=containerimage" \
                                --annotation "org.spacefx.app_name=${APP_NAME}" \
                                --annotation "org.spacefx.app_name=${APP_NAME}" \
                                --annotation "org.spacefx.app_version=${APP_VERSION}" \
                                --annotation "org.spacefx.spacefx_version=${SPACEFX_VERSION}" \
                                --annotation "org.architecture=${ARCHITECTURE}" \
                                --annotation "org.spacefx.app_builddate=${BUILDDATE_VALUE}"
    fi


    cleanup

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main
