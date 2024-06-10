#!/bin/bash
#
# Main entry point to deploy the Microsoft Azure Orbital Space SDK in an airgapped, non-internet connected environment.
#
# Example Usage:
#
#  "bash ./scripts/deploy_spacefx.sh"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../modules/load_modules.sh" $@


############################################################
# Script variables
############################################################

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Main entry point to deploy the Microsoft Azure Orbital Space SDK in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/deploy_spacefx.sh"
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
# Deploy Namespaces
############################################################
function deploy_namespaces(){
    info_log "START: ${FUNCNAME[0]}"

    run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart --set global.namespaces.enabled=true" yaml

    run_a_script "tee ${SPACEFX_DIR}/tmp/yamls/namespaces.yaml > /dev/null << SPACEFX_UPDATE_END
${yaml}
SPACEFX_UPDATE_END"

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} apply -f ${SPACEFX_DIR}/tmp/yamls/namespaces.yaml"

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE

    info_log "Deploying k3s..."
    run_a_script "${SPACEFX_DIR}/scripts/deploy/deploy_k3s.sh"
    info_log "...successfully deployed k3s"

    deploy_namespaces

    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --start"




    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main