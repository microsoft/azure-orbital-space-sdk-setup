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
DEST_STAGE_DIR=""


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
# Check and download k3s
############################################################
function stage_k3s(){
    info_log "START: ${FUNCNAME[0]}"

    local k3s_uri_filename="k3s"
    local url_encoded_k3s_vers=""

    # The k3s version has special characters that need to be URL encoded
    url_encoded_k3s_vers=$(jq -rn --arg x "${VER_K3S:?}" '$x|@uri')

    if [[ "${ARCHITECTURE}" == "arm64" ]]; then
        k3s_uri_filename="k3s-arm64"
    fi

    # Download k3s
    _app_install --app "k3s" --source "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s" --url "https://github.com/k3s-io/k3s/releases/download/${url_encoded_k3s_vers}/${k3s_uri_filename}" --destination "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s"

    # Download k3s install script
    _app_install --app "k3s_install.sh" --source "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s_install.sh" --url "https://get.k3s.io/" --destination "${DEST_STAGE_DIR}/k3s/${VER_K3S}/k3s_install.sh"

    # Download k3s airgap images
    _app_install --app "k3s-airgap-images-${ARCHITECTURE}.tar" --source "${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar" --url "https://github.com/k3s-io/k3s/releases/download/${url_encoded_k3s_vers}/k3s-airgap-images-${ARCHITECTURE}.tar" --destination "${SPACEFX_DIR}/images/${ARCHITECTURE}/k3s-airgap-images-${ARCHITECTURE}.tar"

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
    local tmp_filename="${destination_dir}/helm-${VER_HELM}-linux-${ARCHITECTURE}.tar.gz"
    local download_uri="https://get.helm.sh/helm-${VER_HELM}-linux-${ARCHITECTURE}.tar.gz"

    create_directory "${destination_dir}"

    run_a_script "curl --silent --fail --create-dirs --output ${tmp_filename} -L ${download_uri}"

    info_log "...succesfully downloaded to '${tmp_filename}'.  Extracting to '${destination_dir}'..."

    run_a_script "tar -xf '${tmp_filename}' --directory '${destination_dir}' linux-${ARCHITECTURE}/helm"
    run_a_script "mv ${destination_dir}/linux-${ARCHITECTURE}/helm ${destination_dir}/helm" --disable_log
    run_a_script "rm ${destination_dir}/linux-${ARCHITECTURE} -rf" --disable_log
    run_a_script "rm ${tmp_filename}" --disable_log

    run_a_script "chmod 0755 ${destination_dir}/helm"

    info_log "...successfully extracted helm to '${destination_dir}'"

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log DEST_STAGE_DIR


    # Download CFSSL, jq, yq, regctl
    local VER_CFSSL_no_v="${VER_CFSSL:1}"
    _app_install --app "cfssl" --source "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssl" --url "https://github.com/cloudflare/cfssl/releases/download/${VER_CFSSL}/cfssl_${VER_CFSSL_no_v}_linux_${ARCHITECTURE}" --destination "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssl"
    _app_install --app "cfssljson" --source "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssljson" --url "https://github.com/cloudflare/cfssl/releases/download/${VER_CFSSL}/cfssljson_${VER_CFSSL_no_v}_linux_${ARCHITECTURE}" --destination "${DEST_STAGE_DIR}/cfssl/${VER_CFSSL}/cfssljson"

    _app_install --app "jq" --source "${DEST_STAGE_DIR}/jq/${VER_JQ}/jq" --url "https://github.com/jqlang/jq/releases/download/jq-${VER_JQ:?}/jq-linux-${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/jq/${VER_JQ}/jq"
    _app_install --app "yq" --source "${DEST_STAGE_DIR}/yq/${VER_YQ}/yq" --url "https://github.com/mikefarah/yq/releases/download/v${VER_YQ:?}/yq_linux_${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/yq/${VER_YQ}/yq"
    _app_install --app "regctl" --source "${DEST_STAGE_DIR}/regctl/${VER_REGCTL}/regctl" --url "https://github.com/regclient/regclient/releases/download/${VER_REGCTL:?}/regctl-linux-${ARCHITECTURE:?}" --destination "${DEST_STAGE_DIR}/regctl/${VER_REGCTL}/regctl"

    # Download k3s, kubectl, the airgap images, and the install script
    stage_k3s

    # Run helm last since it's not running in the background task
    stage_helm

    # Wait for any background tasks to finish
    _app_install_wait_for_background_processes


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main