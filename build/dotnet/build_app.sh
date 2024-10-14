#!/bin/bash
#
# Builds and pushes an app built with the Azure Orbital Space SDK.  Will push both a full and base container image.  Will build any nuget packages specified by nuget-project parameter
#
#

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@
############################################################
# Script variables
############################################################
APP_VERSION="0.0.1"
REPO_DIR=""
OUTPUT=""
APP_PROJECT=""
NUGET_PROJECTS=()
ANNOTATION_CONFIG=""
BUILD_OUTPUT_DIR=""
CONTAINER_WORKSPACE_FOLDER=""
DIR_DATESTAMP_VALUE=$(date -u +'%Y-%m-%d-%H-%M-%S')
BUILDDATE_VALUE=$(date -u +'%Y%m%dT%H%M%S')
CONTAINER_BUILD=true
DEVCONTAINER_JSON_FILE=".devcontainer/devcontainer.json"
APP_NAME=""
CONTAINER_ID=""
DEVCONTAINER_JSON=""
BUILD_FROM_GITHUB=false
PUSH_ENABLED=true
############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Builds and pushes the Azure Orbital Space SDK container images and nuget packages"
   echo
   echo "Syntax: bash ./build/dotnet/build_app.sh --repo-dir ~/repos/project_source_code --app-project src/project.csproj --nuget-project src/project.csproj --architecture amd64 --output-dir ./tmp/someDirectory --app-version 0.0.1"
   echo "options:"
   echo "--annotation-config                [OPTIONAL] Filename of the annotation configuration to add to spacefx-config.json.  File must reside within ${SPACEFX_DIR}/config/github/annotations"
   echo "--architecture | -a                [OPTIONAL] The processor architecture for the final build.  Must be either arm64 or amd64.   Allows for cross compiling.  If no architecture is provided, the host architecture will be used."
   echo "--app-project | -p                 [REQUIRED] Relative path to the app's project file from within the devcontainer"
   echo "--app-version | -v                 [REQUIRED] Major version number to assign to the generated nuget package"
   echo "--output-dir | -o                  [REQUIRED] Local output directory to deliver any nuget packages to.  Will automatically get architecture appended.  Parameter is optional if no nuget packages are specified"
   echo "--repo-dir | -r                    [REQUIRED] Local root directory of the repo (will have a subdirectory called '.devcontainer')"
   echo "--nuget-project | -n               [OPTIONAL] Relative path to a nuget project for the service (if applicable) from within the devcontainer.  Will generate a nuget package in the output directory.  Can be passed multiple times"
   echo "--no-container-build               [OPTIONAL] Do not build a container image.  This will only build nuget packages"
   echo "--devcontainer-json                [OPTIONAL] Change the path to the devcontainer.json file.  Default is '.devcontainer/devcontainer.json' in the --repo-dir path"
   echo "--build-from-github                [OPTIONAL] If the destination container registry is different from ghcr.io/microsoft, this will force the container image to be built from the ghcr.io/microsoft container image"
   echo "--no-push                          [OPTIONAL] Do not push the built container image to the container registry.  Useful to locally build and test a container image without pushing it to the registry."
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
        --no-container-build)
            CONTAINER_BUILD=false
        ;;
        --annotation-config)
            shift
            ANNOTATION_CONFIG=$1
            if [[ ! -f "${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG}" ]]; then
                echo "Annotation configuration file '${ANNOTATION_CONFIG}' not found in '${SPACEFX_DIR}/config/github/annotations'"
                show_help
            fi
        ;;
        --no-push)
            PUSH_ENABLED=false
        ;;
        --devcontainer-json)
            shift
            DEVCONTAINER_JSON_FILE=$1
        ;;
        -p|--app-project)
            shift
            APP_PROJECT=$1
            ;;
        -n|--nuget-project)
            shift
            NUGET_PROJECTS+=($1)
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
        -r|--repo-dir)
            shift
            REPO_DIR=$1
            # Removing the trailing slash if there is one
            REPO_DIR=${REPO_DIR%/}
            ;;
        -v|--app-version)
            shift
            APP_VERSION=$1
            ;;
        -o|--output-dir)
            shift
            OUTPUT_DIR=$1
            ;;
        --build-from-github)
            BUILD_FROM_GITHUB=true
            ;;
        *) echo "Unknown parameter passed: $1"; show_help ;;
    esac
    shift
done


if [[ -z "$APP_VERSION" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Devcontainer was not detected.  This script must be run from a Devcontainer"
    show_help
fi

if [[ -z "$ARCHITECTURE" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Mising --architecture parameter"
    show_help
fi

if [[ -z "$REPO_DIR" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Mising --repo-dir parameter"
    show_help
fi

if [[ ! -d "$REPO_DIR" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: --repo-dir '${REPO_DIR}' not found"
    show_help
fi

if [[ ! -f "${REPO_DIR}/${DEVCONTAINER_JSON_FILE}" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: '${REPO_DIR}/${DEVCONTAINER_JSON_FILE}' not found.  Build service requires a devcontainer.json file to run"
    show_help
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    if [ ${#NUGET_PROJECTS[@]} -gt 0 ]; then
        echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Mising --output-dir parameter"
        show_help
    fi
fi

if [[ -z "$APP_PROJECT" ]]; then
    echo "[${SCRIPT_NAME}] [ERROR] ${TIMESTAMP}: Mising --app-project parameter"
    show_help
fi

check_for_cmd --app "docker" --documentation-url "https://docs.docker.com/engine/install/ubuntu/"
check_for_cmd --app "devcontainer" --documentation-url "https://code.visualstudio.com/docs/devcontainers/devcontainer-cli"


############################################################
# Helper function to update an option in devcontainer.json
############################################################
function _update_devcontainer_option(){

    local devfeature_key=""
    local devfeature_value=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --key)
                shift
                devfeature_key=$1
                ;;
            --value)
                shift
                devfeature_value=$1
                ;;
        esac
        shift
    done

    if [[ -z "${DEVCONTAINER_JSON}" ]]; then
        debug_log "DEVCONTAINER_JSON is empty.  Reading values '${REPO_DIR}/${DEVCONTAINER_JSON_FILE}'"
        run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE}" DEVCONTAINER_JSON

        # Remove the extra .configuration.configFilePath that gets added by devcontainer cli
        run_a_script "jq 'del(.configuration.configFilePath)' <<< \${DEVCONTAINER_JSON}" DEVCONTAINER_JSON

        # Remove the extra .configuration that devcontainer cli adds
        run_a_script "jq '.configuration' <<< \${DEVCONTAINER_JSON}" DEVCONTAINER_JSON
    fi

    debug_log "Updating devcontainer json - '${devfeature_key}' = '${devfeature_value}'"

    run_a_script "jq '.features |= with_entries(select(.key | contains(\"spacefx-dev\")) | .value += {\"${devfeature_key}\": \"${devfeature_value}\"})' <<< \${DEVCONTAINER_JSON}" DEVCONTAINER_JSON


    [[ -z "${DEVCONTAINER_JSON}" ]] && exit_with_error "Failed to query devcontainer_json (received empty results).  Please check the logs for more information."

}

############################################################
# Update DevContainer.json config
############################################################
function update_devcontainer_json() {
    info_log "START: ${FUNCNAME[0]}"

    # Disable the cluster to speed up the build
    _update_devcontainer_option --key cluster_enabled --value "false"

    # Make sure we're running in /var/spacedev
    _update_devcontainer_option --key spacefx-dev --value "${SPACEFX_DIR}"

    # Disable setup extraction since we already have the files
    _update_devcontainer_option --key extract_setup_files --value "false"

    # Calculate the app name
    run_a_script "jq -r '.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | .value.app_name' <<< \${DEVCONTAINER_JSON}" APP_NAME
    info_log "...App Name calculated as '$APP_NAME'"

    write_to_file --file "${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json" --file_contents "${DEVCONTAINER_JSON}"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Query the devcontainer for our variables
############################################################
function gather_devcontainer_values(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Gathering devcontainer values..."

    # Calculate the app type
    run_a_script "jq -r '.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | .value.app_type' <<< \${DEVCONTAINER_JSON}" APP_TYPE
    info_log "...App Type calculated as '$APP_TYPE'"

    run_a_script "docker ps -q --filter \"label=devcontainer.local_folder=${REPO_DIR}\"" CONTAINER_ID
    info_log "...container id calculated as '${CONTAINER_ID}'"

    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE} | jq -r '.workspace.workspaceFolder'" CONTAINER_WORKSPACE_FOLDER
    info_log "Container workspace folder calculated as '${CONTAINER_WORKSPACE_FOLDER}'"

    run_a_script "docker inspect ${CONTAINER_ID} | jq -r '.[0].Config.Image'" CONTAINER_IMAGE
    info_log "Container image name calculated as '${CONTAINER_IMAGE}'"

    # Query to get the base image
    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE}" devcontainer_json
    run_a_script "jq -r '.configuration.image' <<< \${devcontainer_json}" DEV_CONTAINER_BASE_IMAGE

    # Query if there's extra packages to apt-get install against
    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE} | jq '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | true'" has_spacefx_feature --ignore_error

    if [[ -n ${has_spacefx_feature} ]]; then
        run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE} | jq -r '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | .value.extra_packages'" extra_packages --ignore_error

        if [[ -n "${extra_packages}" ]]; then
            info_log "Extra packages detected in spacefx-dev container feature (${extra_packages}).  Adding them to container image"
            EXTRA_PKGS="${extra_packages//,/ }"
        fi
    fi

    BUILD_OUTPUT_DIR="${SPACEFX_DIR}/tmp/${APP_NAME}/build-${DIR_DATESTAMP_VALUE}_${ARCHITECTURE}"

    info_log "Generating output directories..."
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json mkdir -p ${BUILD_OUTPUT_DIR}"
    info_log "...output directories generated."

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
    run_a_script "devcontainer up --workspace-folder ${REPO_DIR} --remove-existing-container \
                        --workspace-mount-consistency cached \
                        --id-label devcontainer.local_folder=${REPO_DIR} \
                        --id-label devcontainer.config_file=${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json \
                        --log-level debug \
                        --log-format json \
                        --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json \
                        --default-user-env-probe loginInteractiveShell \
                        --build-no-cache \
                        --remove-existing-container \
                        --mount type=volume,source=vscode,target=/vscode,external=true \
                        --update-remote-user-uid-default on \
                        --mount-workspace-git-root true"

    info_log "Devcontainer built"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Build the nuget package project
############################################################
function build_nuget_package(){

    local project=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --project)
                shift
                project=$1
                ;;
        esac
        shift
    done

    info_log "Checking for '${CONTAINER_WORKSPACE_FOLDER}/${project}' in container"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json test -f \"${CONTAINER_WORKSPACE_FOLDER}/${project}\"" --ignore_error
    if [[ $RETURN_CODE -gt 0 ]]; then
        exit_with_error "Project '${project}' not found in container workspace.  Please check your --nuget-project path and try again"
    fi

    info_log "...found project '${project}'.  Building..."
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json mkdir -p ${BUILD_OUTPUT_DIR}/nuget"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json dotnet restore \"${CONTAINER_WORKSPACE_FOLDER}/${project}\" /p:Version=${APP_VERSION}"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json dotnet build \"${CONTAINER_WORKSPACE_FOLDER}/${project}\" /p:Version=${APP_VERSION} --output \"${BUILD_OUTPUT_DIR}/nuget\" --configuration Release"
    info_log "...project ${project} successfully generated"

}

############################################################
# Build the app that will be backed into a container
############################################################
function build_app(){

    local project=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --project)
                shift
                project=$1
                ;;
        esac
        shift
    done

    info_log "Checking for '${CONTAINER_WORKSPACE_FOLDER}/${project}' in container"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json test -f \"${CONTAINER_WORKSPACE_FOLDER}/${project}\"" --ignore_error
    if [[ $RETURN_CODE -gt 0 ]]; then
        exit_with_error "Project '${project}' not found in container workspace.  Please check your --app-project path and try again"
    fi

    info_log "...found project '${project}'.  Building..."

    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json mkdir -p ${BUILD_OUTPUT_DIR}/app"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json dotnet restore \"${CONTAINER_WORKSPACE_FOLDER}/${project}\" /p:Version=${APP_VERSION}"
    run_a_script "devcontainer exec --workspace-folder ${REPO_DIR} --config ${SPACEFX_DIR}/tmp/${APP_NAME}/devcontainer.json dotnet build \"${CONTAINER_WORKSPACE_FOLDER}/${project}\" /p:Version=${APP_VERSION} --output \"${BUILD_OUTPUT_DIR}/app\" --configuration Release"
    info_log "...project ${project} successfully generated"

}

############################################################
# Copy generated nugets to output directory
############################################################
function copy_to_output_dir(){
    info_log "START: ${FUNCNAME[0]}"

    local subfolder=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --subfolder)
                shift
                subfolder=$1
                ;;
        esac
        shift
    done

    info_log "Copying contents of build output dir '${BUILD_OUTPUT_DIR}' to requested output directory '${OUTPUT_DIR}'..."
    run_a_script "mkdir -p ${OUTPUT_DIR}"
    run_a_script "cp -r ${BUILD_OUTPUT_DIR}/${subfolder} ${OUTPUT_DIR}/${subfolder}"
    info_log "...successfully copied '${BUILD_OUTPUT_DIR}' to '${OUTPUT_DIR}'. "

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    write_parameter_to_log APP_VERSION
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log REPO_DIR
    write_parameter_to_log APP_PROJECT
    write_parameter_to_log BUILDDATE_VALUE
    write_parameter_to_log CONTAINER_BUILD
    write_parameter_to_log ANNOTATION_CONFIG
    write_parameter_to_log BUILD_FROM_GITHUB
    write_parameter_to_log PUSH_ENABLED

    if [[ -n "${ANNOTATION_CONFIG}" ]]; then
        run_a_script "cp ${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG} ${SPACEFX_DIR}/config/${ANNOTATION_CONFIG}" --disable_log
        _annotation_config="--annotation-config ${ANNOTATION_CONFIG}"
        _generate_spacefx_config_json
    fi

    for NUGET_PROJECT in "${NUGET_PROJECTS[@]}"; do
        write_parameter_to_log NUGET_PROJECT
    done

    if [[ "$OUTPUT_DIR" != *"$ARCHITECTURE" ]]; then
        OUTPUT_DIR="${OUTPUT_DIR}/${ARCHITECTURE}"
    fi

    write_parameter_to_log OUTPUT

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

    info_log "Checking for spacefx-dev feature in devcontainer.json..."
    run_a_script "devcontainer read-configuration --workspace-folder ${REPO_DIR} --config ${REPO_DIR}/${DEVCONTAINER_JSON_FILE} | jq '.configuration.features | to_entries[] | select(.key | contains(\"spacefx-dev\")) | true'" has_spacefx_feature --ignore_error
    info_log "Result: ${has_spacefx_feature}"

    [[ -z "${has_spacefx_feature}" ]] && exit_with_error "spacefx-dev feature not found in devcontainer.json.  Please add the feature to the devcontainer.json file before trying to use this script"

    update_devcontainer_json
    provision_devcontainer
    gather_devcontainer_values

    if [ ${#NUGET_PROJECTS[@]} -gt 0 ]; then
        info_log "Building nuget packages..."

        for NUGET_PROJECT in "${NUGET_PROJECTS[@]}"; do
            build_nuget_package --project "${NUGET_PROJECT}"
        done

        copy_to_output_dir --subfolder "nuget"

        info_log "All nuget packages successfully built"
    fi

    build_app --project "${APP_PROJECT}"
    copy_to_output_dir --subfolder "app"

    if [[ "${CONTAINER_BUILD}" == "true" ]]; then
        info_log "Building container image..."

        local extra_cmds=""
        [[ "${PUSH_ENABLED}" == false ]] && extra_cmds="${extra_cmds} --no-push"

        [[ "${BUILD_FROM_GITHUB}" == true ]] && extra_cmds="${extra_cmds} --build-from-github"

        run_a_script "${SPACEFX_DIR}/build/build_containerImage.sh \
                        --dockerfile ${SPACEFX_DIR}/build/dotnet/Dockerfile.app-base \
                        --image-tag ${APP_VERSION}_base \
                        --no-spacefx-dev \
                        --architecture ${ARCHITECTURE} \
                        --repo-dir ${OUTPUT_DIR}/app \
                        --build-arg APP_NAME=${APP_NAME} \
                        --build-arg APP_VERSION=${APP_VERSION} \
                        --build-arg SPACEFX_VERSION=${SPACEFX_VERSION} \
                        --build-arg APP_BUILDDATE=${BUILDDATE_VALUE} \
                        --build-arg ARCHITECTURE=${ARCHITECTURE} \
                        --build-arg WORKING_DIRECTORY=${CONTAINER_WORKSPACE_FOLDER} \
                        --app-name ${APP_NAME} ${_annotation_config} ${extra_cmds}"

        run_a_script "${SPACEFX_DIR}/build/build_containerImage.sh \
                --dockerfile ${SPACEFX_DIR}/build/dotnet/Dockerfile.app \
                --image-tag ${APP_VERSION} \
                --no-spacefx-dev \
                --architecture ${ARCHITECTURE} \
                --repo-dir ${OUTPUT_DIR}/app \
                --build-arg APP_NAME=${APP_NAME} \
                --build-arg APP_VERSION=${APP_VERSION} \
                --build-arg SPACEFX_VERSION=${SPACEFX_VERSION} \
                --build-arg APP_BUILDDATE=${BUILDDATE_VALUE} \
                --build-arg ARCHITECTURE=${ARCHITECTURE} \
                --build-arg WORKING_DIRECTORY=${CONTAINER_WORKSPACE_FOLDER} \
                --app-name ${APP_NAME} ${_annotation_config} ${extra_cmds}"

        info_log "...successfully built container image"
    fi



    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"

}


main
