#!/bin/bash

############################################################
# Install 3p apps to the target host
############################################################
function install_3p_apps() {
    local need_apps_installed=false

    info_log "Checking if third party apps are installed and available..."

    is_cmd_available "yq" has_yq_cmd
    is_cmd_available "jq" has_jq_cmd
    is_cmd_available "regctl" has_regctl_cmd
    is_cmd_available "kubectl" has_kubectl_cmd
    is_cmd_available "cfssl" has_cfssl_cmd
    is_cmd_available "cfssljson" has_cfssljson_cmd
    is_cmd_available "helm" has_helm_cmd


    if [[ $has_yq_cmd == true ]] && [[ $has_jq_cmd == true ]] && [[ $has_regctl_cmd == true ]] && [[ $has_kubectl_cmd == true ]] && [[ $has_cfssl_cmd == true ]] && [[ $has_cfssljson_cmd == true ]] && [[ $has_helm_cmd == true ]]; then
        info_log "All third party apps are installed and available."
        return
    fi

    info_log "Detected missing third party apps.  Starting installation..."

    _stage_3p_apps

    source_dir="${SPACEFX_DIR}/bin/${HOST_ARCHITECTURE}"

    _install_app --app "jq" --source "${source_dir}/jq/${VER_JQ}/jq" --destination "/usr/local/bin/jq"
    _install_app --app "yq" --source "${source_dir}/yq/${VER_YQ}/yq" --destination "/usr/local/bin/yq"
    _install_app --app "regctl" --source "${source_dir}/regctl/${VER_REGCTL}/regctl" --destination "/usr/local/bin/regctl"
    _install_app --app "kubectl" --source "${source_dir}/kubectl/${VER_KUBECTL}/kubectl" --destination "/usr/local/bin/kubectl"
    _install_app --app "cfssl" --source "${source_dir}/cfssl/${VER_CFSSL}/cfssl" --destination "/usr/local/bin/cfssl"
    _install_app --app "cfssljson" --source "${source_dir}/cfssl/${VER_CFSSL}/cfssljson" --destination "/usr/local/bin/cfssljson"
    _install_app --app "helm" --source "${source_dir}/helm/${VER_HELM}/helm" --destination "/usr/local/bin/helm"


    # if [[ "${HOST_ARCHITECTURE}" != "${ARCHITECTURE}" ]]; then
    #     info_log "Cleaning alternative architecture download..."
    #     run_a_script "rm -rf ${SPACEFX_DIR}/bin/${HOST_ARCHITECTURE}"
    #     run_a_script "rm -rf ${SPACEFX_DIR}/images/${HOST_ARCHITECTURE}"
    # fi
}


############################################################
# Helper function to install app to local path
############################################################
function _install_app() {
    local app_name=""
    local source=""
    local destination=""


    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --app)
                shift
                app_name=$1
                ;;
            --source)
                shift
                source=$1
                ;;
            --destination)
                shift
                destination=$1
                ;;
            *) echo "Unknown parameter '$1'"; show_help ;;
        esac
        shift
    done

    is_cmd_available "${app_name}" has_cmd
    if [[ $has_cmd == true ]]; then
        info_log "App '${app_name}' already installed.  Nothing to do"
        return
    fi


    if [[ -z "${app_name}" ]] || [[ -z "${source}" ]] || [[ -z "${destination}" ]]; then
        exit_with_error "Missing required parameters.  Please use --app, --url, and --destination"
    fi

    if [[ -f "${destination}" ]]; then
        info_log "App '${app_name}' already downloaded to '${destination}'.  Nothing to do"
        return
    fi

    info_log "Copying App '${app_name}' from '${source}' to '${destination}'..."
    run_a_script "cp ${source} ${destination}"
    info_log "...successfully copied App '${app_name}' from '${source}' to '${destination}'..."

}

############################################################
# Trigger the staging of 3rd party apps to the directories so we can pull them and install them
############################################################
function _stage_3p_apps(){
    if [[ "${HOST_ARCHITECTURE}" != "${ARCHITECTURE}" ]]; then
        info_log "Downloading 3rd party apps for ${HOST_ARCHITECTURE} architecture..."
        run_a_script "${SPACEFX_DIR}/scripts/stage/stage_3p_apps.sh --architecture ${HOST_ARCHITECTURE}"
    fi
}
