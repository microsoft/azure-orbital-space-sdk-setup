#!/bin/bash
#
# Install k3s within an air-gapped, non-internet connected environment
#
# Example Usage:
#
#  "bash ./scripts/deploy/deploy_k3s.sh"

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
   echo "Downloads the third-party apps used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/deploy/deploy_k3s.sh"
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
# deploys k3s
############################################################
function deploy_k3s_cluster(){
    info_log "START: ${FUNCNAME[0]}"

     local extra_cmds="--write-kubeconfig-mode \"0644\""

    if [[ ! -f "/etc/rancher/k3s/registries.yaml" ]]; then
        info_log "Generating /etc/rancher/k3s/registries.yaml..."
        create_directory "/etc/rancher/k3s"
        run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart --set global.registryRedirect.enabled=true" registries_yaml
        run_a_script "tee /etc/rancher/k3s/registries.yaml > /dev/null << SPACEFX_UPDATE_END
${registries_yaml}
SPACEFX_UPDATE_END"
        info_log "...successfully generated '/etc/rancher/k3s/registries.yaml'"
    fi

    info_log "Checking for K3s..."

    run_a_script "systemctl list-unit-files | grep '^k3s.service'" k3s_installed --ignore_error

    if [[ -n "${k3s_installed}" ]]; then
        info_log "...k3s is installed and activated"
        info_log "END: ${FUNCNAME[0]}"
        return 0
    fi

    info_log "...k3s not found.  Checking prereqs..."

    _check_for_file "${SPACEFX_DIR}/bin/${ARCHITECTURE}/k3s/${VER_K3S}/k3s"
    _check_for_file "${SPACEFX_DIR}/bin/${ARCHITECTURE}/k3s/${VER_K3S}/k3s_install.sh"
    _check_for_file "${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar.gz"

    info_log "...copying files to destinations..."


    [[ ! -d "/usr/local/bin" ]] && create_directory "/usr/local/bin"
    [[ ! -f "/usr/local/bin/k3s" ]] && run_a_script "cp ${SPACEFX_DIR}/bin/${ARCHITECTURE}/k3s/${VER_K3S}/k3s /usr/local/bin/k3s"

    [[ ! -d "/var/lib/rancher/k3s/agent/images" ]] && create_directory "/var/lib/rancher/k3s/agent/images"
    [[ ! -f "/var/lib/rancher/k3s/agent/images/k3s-airgap-images-${ARCHITECTURE}.tar.gz" ]] && run_a_script "cp ${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar.gz /var/lib/rancher/k3s/agent/images/k3s-airgap-images-${ARCHITECTURE}.tar.gz"


    export INSTALL_K3S_SKIP_DOWNLOAD=true
    export INSTALL_K3S_SYMLINK=force
    export INSTALL_K3S_VERSION=${VER_K3S}

    run_a_script "jq -r '.config.clusterDataDir' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" cluster_data_dir
    if [[ -n "${cluster_data_dir}" ]]; then
        export INSTALL_K3S_EXEC="--data-dir ${cluster_data_dir}"
    fi


    run_a_script "${SPACEFX_DIR}/bin/${ARCHITECTURE}/k3s/${VER_K3S}/k3s_install.sh ${extra_cmds}"


    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Wait for k3s to finish deploying by checking for running pods
############################################################
function wait_for_k3s_to_finish_initializing(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Waiting for k3s to finish initializing (max 5 mins)..."

    start_time=$(date +%s)

    # This returns any pods that are running
    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase=Running -A" k3s_deployments --ignore_error

    # This loops and waits for at least 1 pod to flip the running
    while [[ -z $k3s_deployments ]]; do
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase=Running -A" k3s_deployments --ignore_error

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for k3s to finish deploying.  Check if an error has happened, or restart deploy_k3s.sh"
        fi

        info_log "No completed deployments yet.  Rechecking in 2 seconds"
        sleep 2
    done

    info_log "Found a completed deployment.  Waiting for all deployments to finish (max 5 mins)..."

    # This returns any pods that are not completed nor succeeded
    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase!=Running,status.phase!=Succeeded -n kube-system --ignore-not-found" k3s_deployments

    start_time=$(date +%s)

    while [[ -n $k3s_deployments ]]; do
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase!=Running,status.phase!=Succeeded -n kube-system --ignore-not-found" k3s_deployments

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for k3s to finish deploying.  Check if an error has happened, or restart deploy_k3s.sh"
        fi

        info_log "Found deployments still processing.  Rechecking in 2 seconds"
        sleep 2
    done

    info_log "k3s has successfully initialized"


    info_log "FINISHED: ${FUNCNAME[0]}"
}

function main() {

    deploy_k3s_cluster
    wait_for_k3s_to_finish_initializing

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main