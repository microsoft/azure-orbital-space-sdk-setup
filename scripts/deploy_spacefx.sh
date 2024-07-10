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
DEV_ENVIRONMENT=false

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Main entry point to deploy the Microsoft Azure Orbital Space SDK in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/deploy_spacefx.sh"
   echo "options:"
   echo "--dev-environment                  [OPTIONAL] Configure the cluster for development pods"
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
        --dev-environment) DEV_ENVIRONMENT=true ;;
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


############################################################
# Deploys all the services for a service group
############################################################
function deploy_spacefx_service_group(){
    info_log "START: ${FUNCNAME[0]}"

    local service_group=""
    local deploy_group_cmd=""
    local wait_for_deployment=false

    local enabled_filter="prod.enabled"
    [[ "${DEV_ENVIRONMENT}" == true ]] && enabled_filter="dev.enabled"


    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --service_group)
                shift
                service_group=$1
                ;;
            --wait_for_deployment)
                wait_for_deployment=true
                ;;
        esac
        shift
    done

    info_log "Scanning '${service_group}' spacefx services for deploying..."

    run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group} | to_entries[] | select(.value.${enabled_filter} == true) | .key' -r" spacefx_services
    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployments -A -o json" services_deployed_cache --disable_log

    for service in $spacefx_services; do
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.appName' -r" spacefx_service_appName
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.serviceNamespace' -r" spacefx_service_serviceNamespace

        run_a_script "jq -r '.items[] | select(.metadata.name == \"${spacefx_service_appName}\" and (.metadata.namespace == \"${spacefx_service_serviceNamespace}\")) | true' <<< \${services_deployed_cache}" service_deployed

        if [[ "${service_deployed}" == "true" ]]; then
            info_log "...service already deployed.  Nothing to do"
            continue
        fi

        info_log "...adding '${service}'..."
        deploy_group_cmd="${deploy_group_cmd} --set services.${service_group}.${service}.enabled=true"

        debug_log "Checking for hostDirectoryMounts for '${service_group}.${service}'..."
        run_a_script "jq '.config.hostDirectoryMounts.${service_group}.${service}' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_mounts --ignore_error

        [[ "${has_mounts}" == "null" ]] && has_mounts=""

        if [[ -n "${has_mounts}" ]]; then
            debug_log "...hostDirectoryMounts found for '${service_group}.${service}'"

            run_a_script "jq -r '.config.hostDirectoryMounts.${service_group}.${service}[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" host_directory_mount --ignore_error

            host_directory_mount_count=0

            for row in $host_directory_mount; do
                parse_json_line --json "${row}" --property ".name" --result mount_name
                parse_json_line --json "${row}" --property ".hostPath" --result mount_path

                info_log "...adding hostDirectoryMounts '${mount_path}' for '${service_group}.${service}'..."

                deploy_group_cmd="${deploy_group_cmd} --set services.${service_group}.${service}.hostDirectoryMounts[${host_directory_mount_count}].name=${mount_name}  --set services.${service_group}.${service}.hostDirectoryMounts[${host_directory_mount_count}].hostPath=${mount_path}"

                ((host_directory_mount_count = host_directory_mount_count + 1))
            done

        else
            debug_log "...no hostDirectoryMounts found for '${service_group}.${service}'"
        fi
    done

    if [[ -z "${deploy_group_cmd}" ]]; then
        info_log "No services were queued.  Nothing to do"
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    info_log "Successfully queued services for deployment.  Generating yaml for service group '${service_group}'..."

    run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart ${deploy_group_cmd}" yaml --disable_log


    # This is only for debugging as it outputs any secrets to plain text on the disk
    run_a_script "tee ${SPACEFX_DIR}/tmp/yamls/${service_group}.yaml > /dev/null << SPACEFX_UPDATE_END
${yaml}
SPACEFX_UPDATE_END" --disable_log


    info_log "Deploying '${service_group}' spacefx services..."

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} apply -f - <<SPACEFX_UPDATE_END
${yaml}
SPACEFX_UPDATE_END" --disable_log

    if [[ "${wait_for_deployment}" == true ]]; then
        for service in $spacefx_services; do
            run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.appName' -r" service_appName
            run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.serviceNamespace' -r" service_nameSpace

            info_log "...waiting for '${service}' (Deployment Namespace: ${service_nameSpace} Name:${service_appName}) to finish provisioning..."
            wait_for_deployment --namespace "${service_nameSpace}" --deployment "${service_appName}"
            info_log "...'${service}' is online."
        done
    fi

    info_log "Successfully deployed '${service_group}'"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Copies the regctl binary to the deployment service
############################################################
function deploy_regctl_to_deployment_service(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ! -d "${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl" ]]; then
        run_a_script "mkdir -p ${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl"
    fi

    info_log "Copying '${SPACEFX_DIR}/bin/${ARCHITECTURE}/regctl/${VER_REGCTL}' to '${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl/regctl'..."
    run_a_script "cp ${SPACEFX_DIR}/bin/${ARCHITECTURE}/regctl/${VER_REGCTL}/regctl ${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl/regctl"
    info_log "...successfully copied regctl binary to '${SPACEFX_DIR}/tmp/platform-deployment/regctl/regctl'"


    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Run any yaml files found in yamls/deploy directory
############################################################
function deploy_prestaged_yamls(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Deploying any pre-staged yaml files found in '${SPACEFX_DIR}/yamls'..."
    if [[ ! -d "${SPACEFX_DIR}/yamls" ]]; then
        info_log "'${SPACEFX_DIR}/yamls' doesn't exist.  Nothing to do."
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi
    while read -r yamlFile; do
        info_log "Deploying '${yamlFile}'..."
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} apply -f ${yamlFile}" --ignore_error
        if [[ "${RETURN_CODE}" == 0 ]]; then
            info_log "...'${yamlFile}' successfully deployed."
        else
            error_log "...'${yamlFile}' failed to deploy.  See logs for more information."
        fi
    done < <(find "${SPACEFX_DIR}/yamls" -iname "*.yaml")

    info_log "All pre-staged yaml files have been deployed."

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE

    info_log "Deploying k3s..."
    run_a_script "${SPACEFX_DIR}/scripts/deploy/deploy_k3s.sh"
    info_log "...successfully deployed k3s"

    check_and_create_certificate_authority
    deploy_namespaces

    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --start"
    run_a_script "${SPACEFX_DIR}/scripts/deploy/deploy_chart_dependencies.sh"


    run_a_script "jq -r '.config.charts[] | select(.group == \"smb\") | .enabled' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" smb_enabled --disable_log

    if [[ "${smb_enabled}" == "true" ]]; then
        # SMB takes a moment to come online.  We need to wait for it
        deploy_spacefx_service_group --service_group core --wait_for_deployment
    else
        # No SMB means no cross-pod depenendcies.  No need to wait
        deploy_spacefx_service_group --service_group core
    fi


    deploy_spacefx_service_group --service_group platform
    deploy_spacefx_service_group --service_group host

    deploy_regctl_to_deployment_service
    deploy_prestaged_yamls


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main