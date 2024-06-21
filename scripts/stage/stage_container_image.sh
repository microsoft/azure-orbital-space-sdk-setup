#!/bin/bash
#
# Downloads container images and pushes into core-registry for use in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/stage/stage_container_image.sh [--architecture arm64 | amd64] --image"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@

############################################################
# Script variables
############################################################
IMAGES=()

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Downloads the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/stage/stage_chart_dependencies.sh [--architecture arm64 | amd64]"
   echo "options:"
   echo "--architecture | -a                [OPTIONAL] Change the target architecture for download (defaults to current architecture)"
   echo "--image | -i                       [REQUIRED] A container image to download and stage in the format <container_repository>/<image_name>:<tag>.  Can be added multiple times."
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
                exit 1
            fi
            ;;
        -i | --image)
            shift
            image=$1
            image=$(echo "$image" | sed 's/docker.io\/library\///g')
            IMAGES+=($image)
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
# Loop through the images we got and pull them into core-registry
############################################################
stage_images() {
    info_log "START: ${FUNCNAME[0]}"

    local img_count=0
    local worker_pids
    worker_pids=()

    # Loop through the log files and remove any old ones
    while IFS= read -r -d '' worker_log_file; do
        rm "${worker_log_file}"
    done < <(find "${SPACEFX_DIR}/tmp/" -iname "${SCRIPT_NAME}.log.stage_images.*" -type f -print0)

    # Loop through all the service containers and trigger a background task to pull and export them (if necessary)
    for i in "${!IMAGES[@]}"; do
        info_log "Queuing image - ${IMAGES[i]}..."
        write_to_file --file "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.stage_images.${i}.input" --file_contents "${IMAGES[i]}"
        ((img_count = img_count + 1))
        (
            # Reroute the stdout to a file so we can uniquely identify this run
            trap "" HUP
            exec 2> "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.stage_images.${i}"
            exec 0< /dev/null
            exec 1> "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.stage_images.${i}"

            local full_image_name
            full_image_name=$(cat "${SPACEFX_DIR}/tmp/${SCRIPT_NAME}.log.stage_images.${i}.input")

            echo "START:  ${full_image_name}"

            # This removes everything after the last forward slash
            # so ghcr.io/microsoft/image:version becomes ghcr.io/microsoft
            # so myacr.azurecr.io/image:version becomes myacr.azurecr.io
            # so myacr.azurecr.io/test/image/something/image:version becomes myacr.azurecr.io/test/image/something
            local source_registry_with_suffix
            source_registry_with_suffix="${full_image_name%/*}"

            # Now we have to build the destination image name
            # with all prefixes.  This removes everything after the first forward slash
            # so ghcr.io/microsoft/image:version becomes ghcr.io
            # so myacr.azurecr.io/image:version becomes myacr.azurecr.io
            # so myacr.azurecr.io/test/image/something/image:version becomes myacr.azurecr.io
            source_registry="${full_image_name%%/*}"


            # Calculate the new registry name by replacing just the source registry with the destination registry
            # so ghcr.io/microsoft/image:version becomes registry.spacefx.local/microsoft/image:version
            # so myacr.azurecr.io/image:version becomes registry.spacefx.local/image:version
            # so myacr.azurecr.io/test/image/something/image:version becomes registry.spacefx.local/test/image/something/image:version
            destination_full_name=${full_image_name//$source_registry/registry.spacefx.local}

            echo "Copying '${full_image_name}' to '${destination_full_name}'..."

            regctl image copy --platform "linux/$ARCHITECTURE" "${full_image_name}" "${destination_full_name}" \
            || { echo "Failed to copy '${full_image_name}' to '${destination_full_name}'. See above error for details."; return 1; }


            echo "...successfully copied '${full_image_name}' to '${destination_full_name}'."

            echo "END:  ${full_image_name}"
        ) &
        worker_pids+=($!)
        sleep 0.1
    done

    info_log "Service images in queue: ${img_count}.  Waiting for background processes to finish..."

    # Loop through the background pids and get their return codes
    had_error=false
    for pid in "${worker_pids[@]}"; do
        debug_log "Waiting for worker pid: $pid..."
        local return_code
        wait "$pid"
        return_code=$?
        if [[ $return_code -gt 0 ]]; then
            had_error=true
            error_log "Got a return code of $return_code on "
            # Something broke - track it here so we can grab it later
        fi
    done

    info_log "Workers finished.  Adding logs and checking for success..."

    # Loop through the log files and append them to the main log file
    while IFS= read -r -d '' worker_log_file; do
        cat "${worker_log_file}" >>"${LOG_FILE}"
        cat "${worker_log_file}"
        if [[ "$had_error" == false ]]; then
            run_a_script "rm ${worker_log_file}" --disable_log
        fi
    done < <(find "${SPACEFX_DIR}/tmp/" -iname "${SCRIPT_NAME}.log.stage_images.*" -type f -print0)

    if [[ "$had_error" == true ]]; then
        exit_with_error "Detected error in background tasks.  See above and retry"
    fi

    info_log "Containers successfully staged"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

function main() {
    write_parameter_to_log ARCHITECTURE

    for i in "${!IMAGES[@]}"; do
        IMAGE=${IMAGES[i]}
        write_parameter_to_log IMAGE
    done


    if [[ ${#IMAGES[@]} -eq 0 ]]; then
       info_log "No images passed.  Nothing to do"
       info_log "------------------------------------------"
       info_log "END: ${SCRIPT_NAME}"
       return
    fi

    stage_images


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main