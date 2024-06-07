#!/bin/bash
#
#  Pushes a file to a container registry based on the value in config.buildArtifacts or config.extraBuildArtifacts
#
# arguments:
#
# --artifact : path of the file
# --architecture : the processor architecture for the final build.  Must be either arm64 or amd64
# --artifact-version : Semantic version of the artifact
#
# Example Usage:
#
#  "bash ./build/push_build_artifact.sh --artifact /var/spacedev/protos/spacefx/protos/test.proto --architecture amd64 [--artifact-version 0.1.2.3]"

source $(dirname $(realpath "$0"))/../modules/load_modules.sh $@

############################################################
# Script variables
############################################################
DEST_CONTAINER_REGISTRY="" # Registry to push our values to
ARTIFACT=""
ARTIFACT_VERSION=""
ARTIFACT_FILENAME=""
ARTIFACT_DIR=""
DEST_REPO=""
ARTIFACT_HASH=""
ARTIFACT_DIGEST=""
ANNOTATION_CONFIG=""
BUILDDATE_VALUE=$(date -u +'%Y%m%dT%H%M%S')
DEST_TAG=""

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Pushes a file to a container registry.  Configuration data found in config.buildArtifacts or config.extraBuildArtifacts will take precendence over passed configuration items."
   echo
   echo "Syntax: bash ./build/push_build_artifact.sh --artifact /var/spacedev/protos/spacefx/protos/test.proto --architecture amd64 [--artifact-version 0.1.2.3]"
   echo "options:"
   echo "--artifact | -f                      [REQUIRED] Path to the artifact to push.  Must reside within ${SPACEFX_DIR}"
   echo "--artifact-version | -v              [OPTIONAL] Semantic version of the artifact to use if no entry found in config.buildArtifacts or config.extraBuildArtifacts"
   echo "--annotation-config                  [OPTIONAL] Filename of the annotation configuration to add to spacefx-config.json.  File must reside within ${SPACEFX_DIR}/config/github/annotations"
   echo "--architecture | -a                  [REQUIRED] The processor architecture for the final build.  Must be either arm64 or amd64"
   echo "--destination-repo | -d              [OPTIONAL] Override the calculated destination repo for dynamic artifacts.  Note: this will require manual pull to correctly download the artifact"
   echo "--help | -h                          [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -e|--env) echo "[WARNING] DEPRECATED: this parameter has been deprecated and no longer used.  Please update your scripts accordingly." ;;
        -h|--help) show_help ;;
        -f | --artifact)
            shift
            ARTIFACT=$1
        ;;
        --annotation-config)
            shift
            ANNOTATION_CONFIG=$1
            if [[ ! -f "${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG}" ]]; then
                echo "Annotation configuration file '${ANNOTATION_CONFIG}' not found in '${SPACEFX_DIR}/config/github/annotations'"
                show_help
            fi
        ;;
        -v | --artifact-version)
            shift
            ARTIFACT_VERSION=$1
        ;;
        -d | --destination-repo)
            shift
            DEST_REPO=$1
        ;;
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
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done

if [[ -z "$ARCHITECTURE" ]]; then
    error_log "Missing --architecture parameter"
    show_help
fi

# Check if the artifact exists
if [[ ! -f $ARTIFACT ]]; then
    error_log "Artifact '${ARTIFACT}' not found"
    show_help
fi


if [[ -n "${ARTIFACT_VERSION}" ]]; then
    # Regular expression for semantic versioning
    regex="^[0-9]+(\.[0-9]+)?(\.[0-9]+)?(\.[0-9]+)?$"
    # Check if version is a valid semantic version
    if [[ ! $ARTIFACT_VERSION =~ $regex ]]; then
        error_log "Invalid Artifact Version '${ARTIFACT_VERSION}'"
        show_help
    fi
fi

run_a_script "sha256sum ${ARTIFACT}" ARTIFACT_HASH
ARTIFACT_HASH="${ARTIFACT_HASH%% *}"

############################################################
# Check for configuration in buildArtifacts or extraBuildArtifacts
############################################################
function check_for_preset_config() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for preset configuration for '${ARTIFACT}'..."
    run_a_script "basename ${ARTIFACT}" fileName --disable_log
    ARTIFACT_FILENAME="${fileName}"

    run_a_script "jq -r '.config.buildArtifacts[] | select(.file == \"${fileName}\") | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" build_artifact --ignore_error --disable_log

    # We don't have the artifact in the main build artifacts.  Look in extraArtifacts
    if [[ -z "${build_artifact}" ]]; then
        run_a_script "jq -r '.config.extraBuildArtifacts[] | select(.file == \"${fileName}\") | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" build_artifact --ignore_error --disable_log
    fi

    # We don't have the artifact in config - calculate what the parameters should be based on passed parameters
    if [[ -z "${build_artifact}" ]]; then
        info_log "No preset configuration found for '${ARTIFACT}'.  Using passed parameters"

        # Check if the artifact is in SPACEFX_DIR
        if [[ ! $ARTIFACT == $SPACEFX_DIR* ]]; then
            exit_with_error "Dynamic artifacts must reside within ${SPACEFX_DIR}.  '${ARTIFACT}' is not valid."
            show_help
        fi

        run_a_script "dirname ${ARTIFACT}" ARTIFACT_DIR --disable_log

        ARTIFACT_DIR="${ARTIFACT_DIR//$SPACEFX_DIR/}"

        # Removing the first character if it's a slash
        [[ "${ARTIFACT_DIR:0:1}" == "/" ]] && ARTIFACT_DIR="${ARTIFACT_DIR:1}"

        if [[ -z "${DEST_REPO}" ]]; then
            calculate_repo_name_from_filename --filename "${fileName}" --result DEST_REPO
        fi

        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "..found '${fileName}' in build artifacts.  Pulling values"

    parse_json_line --json "${build_artifact}" --property ".directory" --result ARTIFACT_DIR
    parse_json_line --json "${build_artifact}" --property ".repository" --result DEST_REPO
    parse_json_line --json "${build_artifact}" --property ".tag" --result ARTIFACT_VERSION



    info_log "END: ${FUNCNAME[0]}"
}



############################################################
# Update the manifests to the main image so our redirects work as expect
############################################################
function update_annotations_for_new_artifact(){
    info_log "START: ${FUNCNAME[0]}"

    local annotation_arch_prefix="org.spacefx.artifact.${ARCHITECTURE}"
    info_log "Querying for current annotations..."

    run_a_script "regctl manifest get ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG} --format '{{json .}}' | jq -r '.annotations | to_entries[] | @base64 '" current_annotations --disable_log

    local annotations=()
    for annotation in $current_annotations; do
        parse_json_line --json "${annotation}" --property ".key" --result annotation_key
        parse_json_line --json "${annotation}" --property ".value" --result annotation_value

        # Readd the annotations that aren't specific to the architecture we just pushed
        if [[ ! $annotation_key == *$annotation_arch_prefix* ]]; then
            annotations+=("${annotation_key}=${annotation_value}")
        fi
    done

    annotations+=("${annotation_arch_prefix}.hash=${ARTIFACT_HASH}")
    annotations+=("${annotation_arch_prefix}.builddate=${BUILDDATE_VALUE}")


    local annotation_string_for_new_artifact=""

    for annotationpart in "${annotations[@]}"; do
        annotation_string_for_new_artifact="${annotation_string_for_new_artifact} --annotation=${annotationpart}"
    done

    info_log "Updating annotations for ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}..."
    set_annotation_to_image --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}" --full_annotation_string "${annotation_string_for_new_artifact}"
    info_log "...successfully updated annotations for ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}."


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Push A Build Artifact
############################################################
function push_artifact() {
    info_log "START: ${FUNCNAME[0]}"

    local annotations=()
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --annotation)
            shift
            annotations+=($1)
            ;;
        esac
        shift
    done

    local annotation_string=""

    if [[ -n "${GITHUB_ANNOTATION}" ]]; then
        annotations+=("org.opencontainers.image.source=${GITHUB_ANNOTATION}")
    fi

    for annotationpart in "${annotations[@]}"; do
        annotation_string="${annotation_string} --annotation=${annotationpart}"
    done


    info_log "Checking for previous artifact '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}' (${ARCHITECTURE})..."
    run_a_script "regctl manifest get ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG} --format '{{json .}}' | jq -r '.manifests[] | select(.annotations.\"org.spacefx.artifact.architecture\" == \"${ARCHITECTURE}\") | .digest'" remote_file_digests --ignore_error

    if [[ -n "${remote_file_digests}" ]]; then
        for remote_file_digest in $remote_file_digests; do
            info_log "...found previous '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}@${remote_file_digest}' (${ARCHITECTURE}).  Removing..."
            run_a_script "regctl index delete ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG} --digest ${remote_file_digest}"
            info_log "...successfully removed old '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}@${remote_file_digest}' (${ARCHITECTURE})"
        done
    else
        info_log "...no previous '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}' (${ARCHITECTURE}) found."
    fi

    info_log "Pushing artifact for ${ARCHITECTURE}..."
    run_a_script "regctl artifact put   --strip-dirs \
                                        --artifact-type application/vnd.spacefx.${ARCHITECTURE}.buildartifact \
                                        --file-media-type application/vnd.spacefx.${ARCHITECTURE}.buildartifact \
                                        --index ${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG} \
                                        ${annotation_string} \
                                        --subject \"${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}\" \
                                        --file \"${ARTIFACT}\""
    info_log "...successfully pushed ${ARTIFACT} to '${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}'"


    info_log "END: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARTIFACT
    write_parameter_to_log ARTIFACT_VERSION
    write_parameter_to_log ARTIFACT_HASH
    write_parameter_to_log ARCHITECTURE

    check_for_preset_config

    write_parameter_to_log DEST_REPO
    write_parameter_to_log ARTIFACT_FILENAME
    write_parameter_to_log ARTIFACT_DIR
    write_parameter_to_log ARTIFACT_VERSION

    if [[ -n "${ANNOTATION_CONFIG}" ]]; then
        write_parameter_to_log GITHUB_ANNOTATION
        run_a_script "cp ${SPACEFX_DIR}/config/github/annotations/${ANNOTATION_CONFIG} ${SPACEFX_DIR}/config/${ANNOTATION_CONFIG}" --disable_log
        _generate_spacefx_config_json
    fi

    if [[ -z "${ARTIFACT_VERSION}" ]]; then
        exit_with_error "No artifact version found.  Please check your config under '${SPACEFX_DIR}/config' under buildArtifacts or extraBuildArtifacts, or pass via --artifact_version"
    fi

    DEST_ARTIFACT_TAG="${ARTIFACT_VERSION}"
    DEST_SPACEFX_TAG="${SPACEFX_VERSION}"

    # Check if we have a tag suffix from our config file
    run_a_script "jq -r 'if (.config | has(\"tagSuffix\")) then .config.tagSuffix else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" tag_suffix --disable_log

    if [[ -n "${tag_suffix}" ]]; then
        DEST_ARTIFACT_TAG="${ARTIFACT_VERSION}${tag_suffix}"
        DEST_SPACEFX_TAG="${SPACEFX_VERSION}${tag_suffix}"
    fi


    write_parameter_to_log DEST_ARTIFACT_TAG
    write_parameter_to_log DEST_SPACEFX_TAG

    get_registry_with_push_access DEST_CONTAINER_REGISTRY

    write_parameter_to_log DEST_CONTAINER_REGISTRY

    if [[ -z "${DEST_CONTAINER_REGISTRY}" ]]; then
        exit_with_error "No container registries with push access were found.  Can't push an artifact.  Please check your config under '${SPACEFX_DIR}/config' under containerRegisteries with push_enabled=true"
    fi

    # Check if our destination repo has a repositoryPrefix
    run_a_script "jq -r '.config.containerRegistries[] | select(.url == \"${DEST_CONTAINER_REGISTRY}\") | if (has(\"repositoryPrefix\")) then .repositoryPrefix else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" REPO_PREFIX

    if [[ -n "${REPO_PREFIX}" ]]; then
        info_log "Repository Prefix found for ${DEST_CONTAINER_REGISTRY}.  Prefixing with '${REPO_PREFIX}'"
        DEST_REPO="${REPO_PREFIX}/${DEST_REPO}"
    fi

    gen_and_push_manifest --image "${DEST_CONTAINER_REGISTRY}/${DEST_REPO}:${DEST_SPACEFX_TAG}" \
                            --annotation "org.spacefx.artifact.${ARCHITECTURE}.version=${DEST_ARTIFACT_TAG}" \
                            --annotation "org.spacefx.artifact.${ARCHITECTURE}.directory=${ARTIFACT_DIR}" \
                            --annotation "org.spacefx.artifact.filename=${ARTIFACT_FILENAME}" \
                            --annotation "org.spacefx.spacefx_version=${DEST_SPACEFX_TAG}"

    push_artifact --annotation "org.spacefx.item_type=buildartifact" \
                    --annotation "org.spacefx.artifact.${ARCHITECTURE}.version=${DEST_ARTIFACT_TAG}" \
                    --annotation "org.spacefx.artifact.directory=${ARTIFACT_DIR}" \
                    --annotation "org.spacefx.artifact.filename=${ARTIFACT_FILENAME}" \
                    --annotation "org.spacefx.spacefx_version=${DEST_SPACEFX_TAG}" \
                    --annotation "org.architecture=${ARCHITECTURE}" \
                    --annotation "org.spacefx.artifact.builddate=${BUILDDATE_VALUE}" \
                    --annotation "org.spacefx.artifact.hash=${ARTIFACT_HASH}"  \
                    --annotation "org.spacefx.artifact.architecture=${ARCHITECTURE}"

    update_annotations_for_new_artifact

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main

