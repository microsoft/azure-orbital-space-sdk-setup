#!/bin/bash
#
# Downloads the third-party apps used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/stage/stage_3p_apps.sh [--architecture arm64 | amd64]"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@

############################################################
# Script variables
############################################################
WORKER_PIDS=()
LOG_FILES=()
DEST_STAGE_DIR=""
TEMP_DIR=""

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Downloads the third-party apps used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/stage/stage_3p_apps.sh [--architecture arm64 | amd64]"
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

DEST_STAGE_DIR="${SPACEFX_DIR}/bin/${ARCHITECTURE}"

############################################################
# Helper function to download an app to a destination
############################################################
function _download_app() {
    local app_name=""
    local url=""
    local destination=""


    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --app)
                shift
                app_name=$1
                ;;
            --url)
                shift
                url=$1
                ;;
            --destination)
                shift
                destination=$1
                ;;
            *) echo "Unknown parameter '$1'"; show_help ;;
        esac
        shift
    done

    if [[ -z "${app_name}" ]] || [[ -z "${url}" ]] || [[ -z "${destination}" ]]; then
        exit_with_error "Missing required parameters.  Please use --app, --url, and --destination"
    fi

    if [[ -f "${destination}" ]]; then
        info_log "App '${app_name}' already downloaded to '${destination}'.  Nothing to do"
        return
    fi

    info_log "App '${app_name}' not found at '${destination}'.  Adding to download queue"

    (
        set -e
        trap "" HUP
        exec 2> /dev/null
        exec 0< /dev/null
        exec 1> "${TEMP_DIR}/${app_name}.log"
        echo "downloading ${app_name} from ${url} to ${destination}"
        mkdir -p "$(dirname ${destination})"
        curl --silent --fail --create-dirs --output ${destination} -L ${url}
        chmod +x ${destination}
        chmod 755 ${destination}
        echo "downloaded ${app_name} from ${url} to ${destination}"
    ) &

    # Add the PID to the array so we can wait for it to finish
    WORKER_PIDS+=($!)
    LOG_FILES+=("${TEMP_DIR}/${app_name}.log")

}


############################################################
# Check and download k3s
############################################################
function stage_k3s(){
    info_log "START: ${FUNCNAME[0]}"

    local k3s_uri_filename="k3s"
    local url_encoded_k3s_vers=""

    url_encoded_k3s_vers=$(jq -rn --arg x "${VER_K3S:?}" '$x|@uri')

    if [[ "${ARCHITECTURE}" == "arm64" ]]; then
        k3s_uri_filename="k3s-arm64"
    fi

    _download_app --app "k3s" --url "https://github.com/k3s-io/k3s/releases/download/${url_encoded_k3s_vers}/${k3s_uri_filename}" --destination "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s"
    _download_app --app "k3s_install.sh" --url "https://get.k3s.io/" --destination "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s_install.sh"
    _download_app --app "k3s-airgap-images-${ARCHITECTURE}.tar.gz" --url "https://github.com/k3s-io/k3s/releases/download/${url_encoded_k3s_vers}/k3s-airgap-images-${ARCHITECTURE}.tar.gz" --destination "${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar.gz"
    _download_app --app "kubectl" --url "https://dl.k8s.io/release/${VER_KUBECTL}/bin/linux/${ARCHITECTURE}/kubectl" --destination "${DEST_STAGE_DIR}/kubectl/${VER_KUBECTL}/kubectl"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Check and download Helm
############################################################
function stage_helm(){
    info_log "START: ${FUNCNAME[0]}"

    local destination="${DEST_STAGE_DIR}/helm/${VER_HELM}/helm"
    local destination_dir="$(dirname ${destination})"
    if [[ -f "${destination}" ]]; then
        info_log "App 'helm' already downloaded to '${destination}'.  Nothing to do"
        return
    fi

    # Helm has to be downloaded and untarred, so we run it explicitly

    local tmp_filename="${DEST_STAGE_DIR}/tmp/helm-${VER_HELM}-linux-${ARCHITECTURE}.tar.gz"
    local download_uri="https://get.helm.sh/helm-${VER_HELM}-linux-${ARCHITECTURE}.tar.gz"

    create_directory "${destination_dir}"

    run_a_script "curl --silent --fail --create-dirs --output ${tmp_filename} -L ${download_uri}"

    info_log "...succesfully downloaded to '${tmp_filename}'.  Extracting to '${destination_dir}'..."

    run_a_script "tar -xf '${tmp_filename}' --directory '${destination_dir}' linux-${ARCHITECTURE}/helm"
    run_a_script "mv ${destination_dir}/linux-${ARCHITECTURE}/helm ${destination_dir}/helm"
    run_a_script "rm ${destination_dir}/linux-${ARCHITECTURE} -rf"
    run_a_script "rm ${tmp_filename}"

    run_a_script "chmod 0755 ${destination_dir}/helm"

    info_log "...successfully extracted helm to '${destination_dir}'"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Wait for workers to finish
############################################################
function wait_for_workers(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Waiting for background processes to finish..."

    worker_failed=false
    local index=0

    for pid in "${WORKER_PIDS[@]}"; do
        wait "$pid"
        RETURN_CODE=$?
        if [[ $RETURN_CODE -gt 0 ]]; then
            worker_failed=true
            error_log "Failure detected in background worker.  Return code: ${RETURN_CODE}.  Log File: '${LOG_FILES[$index]}'"
            run_a_script "cat ${LOG_FILES[$index]}" log_output
            error_log "${log_output}"
        fi
         ((index++))
    done


    if [[ "${worker_failed}" == true ]]; then
        exit_with_error "Failure detected in background processes.  See above errors and retry"
    fi

    info_log "...background processes finished successfully."

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log DEST_STAGE_DIR

    run_a_script "mktemp -d" TEMP_DIR --disable_log
    write_parameter_to_log TEMP_DIR

    local VER_CFSSL_no_v="${VER_CFSSL:1}"
    _download_app --app "cfssl" --url "https://github.com/cloudflare/cfssl/releases/download/${VER_CFSSL}/cfssl_${VER_CFSSL_no_v}_linux_${ARCHITECTURE}" --destination "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssl"
    _download_app --app "cfssljson" --url "https://github.com/cloudflare/cfssl/releases/download/${VER_CFSSL}/cfssl_${VER_CFSSL_no_v}_linux_${ARCHITECTURE}" --destination "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssljson"

    _download_app --app "jq" --url "https://github.com/jqlang/jq/releases/download/jq-${VER_JQ:?}/jq-linux-${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/jq/${VER_JQ}/jq"
    _download_app --app "yq" --url "https://github.com/mikefarah/yq/releases/download/v${VER_YQ:?}/yq_linux_${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/yq/${VER_YQ}/yq"
    _download_app --app "regctl" --url "https://github.com/regclient/regclient/releases/download/${VER_REGCTL:?}/regctl-linux-${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/regctl/${VER_REGCTL}/regctl"

    stage_k3s

    # Run helm last since it's not running in the background task.
    stage_helm

    wait_for_workers

    run_a_script "rm -rf ${TEMP_DIR}" --disable_log

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main