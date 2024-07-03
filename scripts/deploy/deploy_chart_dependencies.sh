#!/bin/bash
#
# Deploys the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/deploy/deploy_chart_dependencies.sh"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@ --no_internet

############################################################
# Script variables
############################################################



############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Deploys the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/deploy/deploy_chart_dependencies.sh"
   echo "options:"
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
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done


############################################################
# deploys nvidia plugin
############################################################
function deploy_nvidia_plugin(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking if nVidia GPU plugin is requested..."
    run_a_script "jq -r '.config.charts[] | select(.group == \"nvidia_gpu\") | .enabled' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" nvidia_enabled --disable_log

    if [[ "${nvidia_enabled}" == "false" ]]; then
        info_log "nVidia GPU is disabled (from config).  Nothing to do"
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi


    info_log "Checking for nvidia plugin..."
    run_a_script "helm --kubeconfig ${KUBECONFIG} list --all-namespaces | grep 'nvdp'" has_plugin --ignore_error

    if [[ -n "${has_plugin}" ]]; then
        info_log "...found nvidia plugin.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return 0
    fi

    # info_log "nvidia plugin not found...Checking for nVidia GPU..."

    # is_cmd_available "nvidia-smi" has_cmd

    # # shellcheck disable=SC2154
    # if [[ "${has_cmd}" == false ]]; then
    #     warn_log "nvidia-smi not found.  Unable to deploy GPU components"
    #     info_log "------------------------------------------"
    #     info_log "END: ${SCRIPT_NAME}"
    #     return
    # fi

    # run_a_script "nvidia-smi --list-gpus | grep \"GPU\"" has_gpu --ignore_error

    # if [[ -z "$has_gpu" ]]; then
    #     warn_log "nvidia-smi is not able to find the GPU ('nvidia-smi --list-gpus').  Please check your driver and rerun"
    #     info_log "------------------------------------------"
    #     info_log "END: ${SCRIPT_NAME}"
    #     return
    # fi

    # info_log "...GPU found.  Checking if nVidia plugin is staged..."

    if [[ ! -e "/dev/nvhost-gpu" ]]; then
        exit_with_error "nVidia GPU Plugin requested, but no gpu detected in drivers (missing '/dev/nvhost-gpu').  Please check drivers and retry deployment."
    fi


    run_a_script "jq -r '.config.charts[] | select(.group == \"nvidia_gpu\") | .version' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" nvidia_gpu_chart_version

    debug_log "...nVidia version calculated as '${nvidia_gpu_chart_version}'"

    info_log "Looking for '${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}/nvidia-device-plugin-${nvidia_gpu_chart_version}.tgz'..."

    if [[ ! -f "${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}/nvidia-device-plugin-${nvidia_gpu_chart_version}.tgz" ]]; then
        exit_with_error "'${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}/nvidia-device-plugin-${nvidia_gpu_chart_version}.tgz' not found.  Please restage spacefx with the --nvidia-gpu-plugin switch and redeploy, or disable the gpu via config (/var/spacedev/config/*.yaml -> config.charts.nvidia_gpu.enabled)"
    fi

    info_log "...found '${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}/nvidia-device-plugin-${nvidia_gpu_chart_version}.tgz'.  Installing plugin..."

    run_a_script "helm --kubeconfig ${KUBECONFIG} show values ${SPACEFX_DIR}/chart | yq '.global.containerRegistry'" _containerRegistry
    run_a_script "jq -r '.config.charts[] | select(.group == \"nvidia_gpu\") | .containers[0].repository' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" _repository

    run_a_script "helm --kubeconfig ${KUBECONFIG} install nvdp \
                    ${SPACEFX_DIR}/bin/${ARCHITECTURE}/nvidia_plugin/${nvidia_gpu_chart_version}/nvidia-device-plugin-${nvidia_gpu_chart_version}.tgz \
                    --wait --wait-for-jobs \
                    --create-namespace \
                    --set allowDefaultNamespace=true \
                    --timeout 1h \
                    --set image.repository=${_containerRegistry}/${_repository} \
                    --set runtimeClassName=nvidia" nvidia_install

    info_log "...successfully deployed SMB plugin"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# deploys smb plugin
############################################################
function deploy_smb_plugin(){
    info_log "START: ${FUNCNAME[0]}"

    run_a_script "jq -r '.config.charts[] | select(.group == \"smb\") | .enabled' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" smb_enabled --disable_log

    if [[ "${smb_enabled}" == "false" ]]; then
        info_log "SMB is disabled (from config).  Skipping SMB plugin deployment"
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi


    info_log "Checking for SMB plugin..."
    run_a_script "helm --kubeconfig ${KUBECONFIG} list --all-namespaces | grep 'csi-driver-smb'" has_smb_plugin --ignore_error

    if [[ -n "${has_smb_plugin}" ]]; then
        info_log "...found SMB plugin."
        info_log "...waiting for complete deployment..."
        wait_for_namespace "default"
        info_log "...smb successfully deployed"
        info_log "END: ${FUNCNAME[0]}"
        return 0
    fi

    info_log "...SMB plugin not found.  Deploying..."

    run_a_script "jq -r '.config.charts[] | select(.group == \"smb\") | .version' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" smb_version --disable_log


    run_a_script "helm --kubeconfig ${KUBECONFIG} install csi-driver-smb \
                    ${SPACEFX_DIR}/chart/charts/csi-driver-smb-v${smb_version}.tgz \
                    --wait --wait-for-jobs" smb_install

    info_log "...successfully deployed SMB plugin"

    info_log "FINISHED: ${FUNCNAME[0]}"
}



############################################################
# deploys dapr plugin
############################################################
function deploy_dapr_plugin(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for dapr plugin..."
    run_a_script "helm --kubeconfig ${KUBECONFIG} list --all-namespaces | grep 'dapr'" has_dapr_plugin --ignore_error
    run_a_script "jq -r '.config.charts[] | select(.group == \"dapr\") | .namespace' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" dapr_namespace

    if [[ -n "${has_dapr_plugin}" ]]; then
        info_log "...found dapr plugin."
        info_log "...waiting for complete deployment..."
        wait_for_namespace "${dapr_namespace}"
        info_log "...dapr successfully deployed"
        info_log "END: ${FUNCNAME[0]}"
        return 0
    fi

    info_log "...dapr plugin not found.  Deploying..."


    run_a_script "jq -r '.config.charts[] | select(.group == \"dapr\") | .version' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" dapr_version

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get namespaces | grep '${dapr_namespace}'" has_namespace --ignore_error

    if [[ -z "${has_namespace}" ]]; then
        info_log "Creating namespace '${dapr_namespace}'..."
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} create namespace ${dapr_namespace}"
        info_log "...successfully created namespace '${dapr_namespace}'."
    fi


    run_a_script "helm --kubeconfig ${KUBECONFIG} install dapr \
            ${SPACEFX_DIR}/chart/charts/dapr-${dapr_version}.tgz \
            --wait --wait-for-jobs \
            --namespace=${dapr_namespace} \
            --wait --timeout 1h --set global.ha.enabled=false \
            --set global.logAsJson=true \
            --set dapr_placement.logLevel=debug \
            --set dapr_sidecar_injector.sidecarImagePullPolicy=IfNotPresent \
            --set global.imagePullPolicy=IfNotPresent \
            --set global.mtls.enabled=true \
            --set dapr_placement.cluster.forceInMemoryLog=true \
            --set dapr_dashboard.enabled=false"

    info_log "...successfully deployed dapr plugin"

    info_log "Waiting for dapr deployment to finish..."
    wait_for_namespace "${dapr_namespace}"



    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# deploys dapr plugin
############################################################
function wait_for_namespace(){

    local namespace=$1

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase!=Running,status.phase!=Succeeded -n ${namespace} --ignore-not-found" pod_pending

    start_time=$(date +%s)

    while [[ -n $pod_pending ]]; do
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase!=Running,status.phase!=Succeeded -n ${namespace} --ignore-not-found" pod_pending

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for k3s to finish deploying.  Check if an error has happened, or restart deploy_spacefx.sh"
        fi

        info_log "Found pods still processing.  Rechecking in 2 seconds"
        sleep 2
    done
}

function main() {

    deploy_smb_plugin
    deploy_dapr_plugin
    deploy_nvidia_plugin

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main