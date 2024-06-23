#!/bin/bash
#
# Downloads a build artifact (file) from a container registry for use in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/stage/stage_build_artifact.sh [--architecture arm64 | amd64] --image"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@

############################################################
# Script variables
############################################################
ARTIFACTS=()
_ARTIFACT_COUNT=0

DELAY_SECS="0" # Number of seconds to delay between each pass

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Downloads the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/stage/stage_chart_dependencies.sh [--architecture arm64 | amd64]"
   echo "options:"
   echo "--artifact | -f                    [REQUIRED] name of the artifact to pull.  Can be passed multiple times"
   echo "--architecture | -a                [OPTIONAL] Change the target architecture for download (defaults to current architecture)"
   echo "--add-delay-secs | -w              [OPTIONAL] Add number of seconds between each push to prevent overloading to container registry"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options.
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
            fi
            ;;
        -w | --add-delay-secs)
            shift
            DELAY_SECS=$1
            if [[ ! "$DELAY_SECS" =~ ^[0-9]+$ ]]; then
                echo "--add-delay-secs must be a number.  '${DELAY_SECS}' is not valid."
                show_help
            fi
        ;;
        -f | --artifact)
            shift
            _artifact_file=$(basename $1)
            ARTIFACTS+=("$_artifact_file")
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
# Loop through the ARTIFACTS we got and pull them into core-registry
############################################################
stage_artifacts() {
    info_log "START: ${FUNCNAME[0]}"

    local file_count=0
    local worker_pids
    worker_pids=()

    # Loop through all the service containers and trigger a background task to pull and export them (if necessary)
    for i in "${!ARTIFACTS[@]}"; do
        artifact="${ARTIFACTS[i]}"
        info_log "Queuing artifact - ${artifact}..."
        ((file_count = file_count + 1))
        (
            download_artifact "$i" "$artifact"
        ) &
        worker_pids+=($!)
        sleep 0.1
    done

    info_log "Service ARTIFACTS in queue: ${file_count}.  Waiting for background processes to finish..."

    # Loop through the background pids and get their return codes
    had_error=false
    for pid in "${worker_pids[@]}"; do
        debug_log "Waiting for worker pid: $pid..."
        local return_code
        wait "$pid"
        return_code=$?
        if [[ $return_code -gt 0 ]]; then
            had_error=true
            error_log "Got a return code of $return_code on worker pid '$pid'"
            # Something broke - track it here so we can grab it later
        fi
    done

    info_log "Workers finished.  Adding logs and checking for success..."

    for i in "${!ARTIFACTS[@]}"; do
        artifact="${ARTIFACTS[i]}"
        log_file_suffix=$(echo -n "$artifact" | base64 --wrap=0)
        _worker_log_file="${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.${log_file_suffix}"
        if [[ -f "${_worker_log_file}" ]]; then
            cat "${_worker_log_file}" >>"${LOG_FILE}"
            cat "${_worker_log_file}"
            if [[ "$had_error" == false ]]; then
                run_a_script "rm ${_worker_log_file}" --disable_log
            fi
        fi
    done

    if [[ "$had_error" == true ]]; then
        exit_with_error "Detected error in background tasks.  See above and retry"
    fi

    info_log "Build artifacts successfully staged"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Processing function for build artifacts
############################################################
function download_artifact() {
    local i="$1"
    local fileName="$2"
    log_file_suffix=$(echo -n "$artifact" | base64 --wrap=0)
    # Reroute the stdout to a file so we can uniquely identify this run
    trap "" HUP
    exec 2> "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.${log_file_suffix}"
    exec 0< /dev/null
    exec 1> "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.${log_file_suffix}"

    local static_artifact=true
    local artifact_directory=""
    local artifact_repo=""
    local artifact_tag=""
    artifact_full_image_name=""
    artifact_manifest=""
    artifact_hash=""
    local_artifact_hash=""

    info_log "Calculating values for '${fileName}'..."

    run_a_script "jq -r '.config.buildArtifacts // empty | map(select(.file == \"${fileName}\")) | if length > 0 then .[0] | @base64 else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" build_artifact --disable_log --ignore_error

    if [[ -z "${build_artifact}" ]]; then
        # We don't have the artifact in the main build artifacts.  Look in extraArtifacts
        run_a_script "jq -r '.config.extraArtifacts // empty | map(select(.file == \"${fileName}\")) | if length > 0 then .[0] | @base64 else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" build_artifact --disable_log --ignore_error
    fi

    # Found the artifact - parse the values
    if [[ -n "${build_artifact}" ]]; then
        info_log "..found '${fileName}' in build artifacts."
        parse_json_line --json "${build_artifact}" --property ".directory" --result artifact_directory
        parse_json_line --json "${build_artifact}" --property ".repository" --result artifact_repo
        parse_json_line --json "${build_artifact}" --property ".tag" --result artifact_tag
    fi

    # We didn't find the artifact - try and grab it dynamically
    if [[ -z "${build_artifact}" ]]; then
        static_artifact=false
        info_log "..'${fileName}' not found in build artifacts.  Dynamically calculating values..."

        calculate_repo_name_from_filename --filename "${fileName}" --result artifact_repo
        artifact_tag="${SPACEFX_VERSION}"

        calculate_tag_from_channel --tag "${artifact_tag}" --result artifact_tag
    fi

    info_log "...calculating container registry for '${artifact_repo}:${artifact_tag}'..."
    find_registry_for_image "${artifact_repo}:${artifact_tag}" artifact_registry

    if [[ -z "${artifact_registry}" ]]; then
        exit_with_error "Unable to find a registry for '${artifact_repo}:${artifact_tag}'"
    fi

    info_log "Found '${fileName}' in registry '${artifact_registry}' (${artifact_registry}/${artifact_repo}:${artifact_tag})"

    if [[ "${static_artifact}" == "false" ]]; then
        get_image_name --registry "${artifact_registry}" --repo "${artifact_repo}" --result artifact_full_image_name

        run_a_script "regctl manifest get ${artifact_full_image_name}:${artifact_tag} --format '{{json .}}'" artifact_manifest

        run_a_script "jq '.manifests[] | select(.annotations.\"org.architecture\" == \"${ARCHITECTURE}\") | length > 0'  <<< \${artifact_manifest}" has_manifests

        if [[ -z "${has_manifests}" ]]; then
            exit_with_error "Build artifact '${fileName}' ('${artifact_full_image_name}:${artifact_tag}') doesn't have an item for architecture '${ARCHITECTURE}' in the container registry ${artifact_registry}.  Please push a build artifact for architecture '${ARCHITECTURE}' to the registry and try again."
        fi

        debug_log "Found manifest for architecture '${ARCHITECTURE}'."
        run_a_script "jq -r '.manifests[] | select(.artifactType == \"application/vnd.spacefx.${ARCHITECTURE}.buildartifact\") | .annotations.\"org.spacefx.artifact.directory\"' <<< \${artifact_manifest}" artifact_directory
        run_a_script "jq -r '.manifests[] | select(.artifactType == \"application/vnd.spacefx.${ARCHITECTURE}.buildartifact\") | .annotations.\"org.spacefx.artifact.hash\"' <<< \${artifact_manifest}" artifact_hash
    else
        artifact_full_image_name="${artifact_repo}/${artifact_repo}:${artifact_tag}"
    fi

    info_log "Artifact:         ${fileName}"
    info_log "Full Image Name:  ${artifact_full_image_name}"
    info_log "Directory:        ${artifact_directory}"
    info_log "Hash:             ${artifact_hash}"
    info_log "Repository:       ${artifact_repo}"
    info_log "Tag:              ${artifact_tag}"
    info_log "Static Artifact:  ${static_artifact}"

    create_directory "${SPACEFX_DIR}/${artifact_directory}"
    calculate_hash_for_file --file "${SPACEFX_DIR}/${artifact_directory}/${fileName}" --result local_artifact_hash --ignore_missing

    info_log "Local Hash:       ${local_artifact_hash}"

    if [[ "${artifact_hash}" == "${local_artifact_hash}" ]]; then
        info_log "Hash for '${SPACEFX_DIR}/${artifact_directory}/${fileName}' matches container registry hash ('${local_artifact_hash}' = '${artifact_hash}').  Nothing to do."
        return
    fi

    info_log "Hash for '${SPACEFX_DIR}/${artifact_directory}/${fileName}' doesn't match container registry hash ('${local_artifact_hash}' <> '${artifact_hash}')."
    info_log "Downloading '${artifact_full_image_name}:${artifact_tag}' to '${SPACEFX_DIR}/${artifact_directory}/${fileName}'..."


    run_a_script "regctl artifact get ${artifact_full_image_name}:${artifact_tag} --output ${SPACEFX_DIR}/${artifact_directory} --filter-artifact-type application/vnd.spacefx.${ARCHITECTURE}.buildartifact"
    info_log "...successfully downloaded '${artifact_full_image_name}:${artifact_tag}' to '${SPACEFX_DIR}/${artifact_directory}/${fileName}'."

}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log DELAY_SECS

    for i in "${!ARTIFACTS[@]}"; do
        ARTIFACT=${ARTIFACTS[i]}
        write_parameter_to_log ARTIFACT
    done

    if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
       info_log "No artifacts passed.  Nothing to do"
       info_log "------------------------------------------"
       info_log "END: ${SCRIPT_NAME}"
       return
    fi


    stage_artifacts



    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main
