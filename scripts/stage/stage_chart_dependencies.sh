#!/bin/bash
#
# Downloads the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/stage/stage_chart_dependencies.sh [--architecture arm64 | amd64]"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@

############################################################
# Script variables
############################################################
NVIDIA_GPU_PLUGIN=false

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
# Download the GPU components for nVidia
############################################################
function stage_nvidia_plugin() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking if nVidia GPU plugin is requested..."
    run_a_script "jq -r '.config.charts[] | select(.group == \"nvidia_gpu\") | .enabled' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" nvidia_enabled --disable_log

    if [[ "${nvidia_enabled}" == "false" ]]; then
        info_log "nVidia GPU is disabled (from config).  Skipping nVidia plugin staging"
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    info_log "Calculating nvidia plugin version..."

    run_a_script "jq -r '.config.charts[] | select(.group == \"nvidia_gpu\") | .version' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" nvidia_gpu_chart_version

    local dest_dir="${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}"

    info_log "Looking for '${dest_dir}/nvidia_plugin-${INSTALL_NVIDIA_PLUGIN}.tgz'..."

    if [[ ! -f "${dest_dir}/nvidia_plugin-${INSTALL_NVIDIA_PLUGIN}.tgz" ]]; then
        info_log "...not found.  Downloading..."
        create_directory "${dest_dir}"
        run_a_script "helm --kubeconfig ${KUBECONFIG} repo add nvdp https://nvidia.github.io/k8s-device-plugin"
        run_a_script "helm --kubeconfig ${KUBECONFIG} pull nvdp/nvidia-device-plugin --destination ${dest_dir} --version ${nvidia_gpu_chart_version}"
        info_log "...successfully downloaded to '${dest_dir}/nvidia_plugin-${INSTALL_NVIDIA_PLUGIN}.tgz'"
    else
        info_log "...found '${dest_dir}/nvidia_plugin-${INSTALL_NVIDIA_PLUGIN}.tgz'"
    fi


    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Downloads the backend charts used by the Microsoft Azure Orbital Space SDK Helm Chart
############################################################
function stage_dependent_charts(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Staging chart dependencies..."
    run_a_script "helm --kubeconfig ${KUBECONFIG} dependency update ${SPACEFX_DIR}/chart"
    info_log "...successfully staged chart dependencies"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Downloads the container images of the backend charts used by the Microsoft Azure Orbital Space SDK Helm Chart
############################################################
function stage_dependent_charts_images(){
    info_log "START: ${FUNCNAME[0]}"

    run_a_script "jq -r '.config.charts[].group' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" chart_groups

    local stage_container_cmd=""

    for container_type in $chart_groups; do
        if [[ "${container_type}" == "nvidia_gpu" ]] && [[ "${NVIDIA_GPU_PLUGIN}" == false ]]; then
            continue
        fi

        run_a_script "jq -r '.config.charts[] | select(.group == \"${container_type}\" and .enabled == true) | .containers[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" chart_containers

        for container in $chart_containers; do
            parse_json_line --json "${container}" --property ".repository" --result repository
            parse_json_line --json "${container}" --property ".tag" --result tag
            parse_json_line --json "${container}" --property ".registry" --result registry

            tar_fileName="${container_type}_${repository}.${tag}.tar"
            tar_fileName=${tar_fileName//\//_} # Replace slashed with underscores
            stage_container_cmd="${stage_container_cmd} --image ${registry}/${repository}:${tag}"
            debug_log "Adding ${registry}/${repository}:${tag} (${tar_fileName}) to stage queue"
        done
    done

    if [[ -z "${stage_container_cmd}" ]]; then
        info_log "No charts have any containers to stage.  Nothing to do"
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    run_a_script "${SPACEFX_DIR}/scripts/stage/stage_container_image.sh --architecture ${ARCHITECTURE} ${stage_container_cmd}"

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE

    stage_nvidia_plugin
    stage_dependent_charts
    stage_dependent_charts_images

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main