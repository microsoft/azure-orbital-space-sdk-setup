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
    _check_for_file "${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar"

    info_log "...copying files to destinations..."


    [[ ! -d "/usr/local/bin" ]] && create_directory "/usr/local/bin"
    run_a_script "cp ${SPACEFX_DIR}/bin/${ARCHITECTURE}/k3s/${VER_K3S}/k3s /usr/local/bin/k3s"

    [[ ! -d "/var/lib/rancher/k3s/agent/images" ]] && create_directory "/var/lib/rancher/k3s/agent/images"
    run_a_script "cp ${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar /var/lib/rancher/k3s/agent/images/k3s-airgap-images-${ARCHITECTURE}.tar"


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
# Check if the images need to be loaded into k3s
############################################################
function load_images_to_k3s(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Validating images are loaded for k3s..."

    if [[ ! -f "/etc/systemd/system/k3s.service" ]]; then
        info_log "/etc/systemd/system/k3s.service not found.  Nothing to do."
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    run_a_script "grep -q -- \"--docker\" \"/etc/systemd/system/k3s.service\"" --ignore_error

    if [[ $RETURN_CODE -eq 0 ]]; then
        info_log "...docker detected.  Validating images via docker..."
        load_images_to_k3s_docker
    else
        info_log "...docker not detected.  Validating images via ctr..."
        load_images_to_k3s_ctr
    fi

    info_log "Validated images are loaded"

    info_log "FINISHED: ${FUNCNAME[0]}"
}


############################################################
# Check if the images need to be loaded into k3s (via docker)
############################################################
function load_images_to_k3s_ctr(){
    info_log "START: ${FUNCNAME[0]}"

    start_time=$(date +%s)


    is_cmd_available "ctr" has_ctr_cmd
    while [[ "${has_ctr_cmd}" == "false" ]]; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for k3s to come online."
        fi

        info_log "...ctr not available yet.  Rechecking in 5 seconds..."
        sleep 5
        is_cmd_available "ctr" has_ctr_cmd
    done

    info_log "ctr is available.  Checking if images are needed..."
    k3s_images=("klipper-helm" "klipper-lb" "local-path-provisioner" "mirrored-coredns-coredns" "mirrored-library-busybox" "mirrored-library-traefik" "mirrored-metrics-server" "mirrored-pause")

    run_a_script "ctr images list" ctr_images

    needs_images="false"

    for k3s_image in "${k3s_images[@]}"; do
        if [[ "$ctr_images" != *"$k3s_image"* ]]; then
            needs_images="true"
        fi
    done

    if [[ "${needs_images}" == "true" ]]; then
        info_log "Detected missing mirrored images.  Loading from '${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar'..."
        run_a_script "ctr images import ${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar"
        info_log "Images successfully imported"
    else
        info_log "All k3s images are already loaded.  Nothing to do."
    fi


    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Check if the images need to be loaded into k3s (via docker)
############################################################
function load_images_to_k3s_docker(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking if images are needed (docker)..."
    k3s_images=("klipper-helm" "klipper-lb" "local-path-provisioner" "mirrored-coredns-coredns" "mirrored-library-busybox" "mirrored-library-traefik" "mirrored-metrics-server" "mirrored-pause")

    run_a_script "docker images" ctr_images

    needs_images="false"

    for k3s_image in "${k3s_images[@]}"; do
        if [[ "$ctr_images" != *"$k3s_image"* ]]; then
            needs_images="true"
        fi
    done

    if [[ "${needs_images}" == "true" ]]; then
        info_log "Detected missing k3s images.  Loading from '${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar'..."
        run_a_script "docker load --input ${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar"
        info_log "Images successfully imported"
    else
        info_log "All k3s images are already loaded.  Nothing to do."
    fi


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
    load_images_to_k3s
    wait_for_k3s_to_finish_initializing

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main