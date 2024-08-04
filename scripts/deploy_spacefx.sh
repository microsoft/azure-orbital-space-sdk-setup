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
        --dev-environment) echo "--dev-environment is DEPRECATED.  Dev-Environment is calculated during staging" ;;
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
    run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.global.security.forceNonRoot' -r" spacefx_forceNonRoot

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployments -A -o json" services_deployed_cache --disable_log

    for service in $spacefx_services; do
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.appName' -r" spacefx_service_appName
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.serviceNamespace' -r" spacefx_service_serviceNamespace
        run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group}.${service}.runAsUserId' -r" spacefx_service_userid


        run_a_script "jq -r '.items[] | select(.metadata.name == \"${spacefx_service_appName}\" and (.metadata.namespace == \"${spacefx_service_serviceNamespace}\")) | true' <<< \${services_deployed_cache}" service_deployed

        if [[ "${service_deployed}" == "true" ]]; then
            info_log "...service already deployed.  Nothing to do"
            continue
        fi

        # Create users and groups if the service needs one
        if [[ "${spacefx_forceNonRoot}" == "true" ]] && [[ "${spacefx_service_userid}" != "null" ]]; then
            info_log "...checking if group '${spacefx_service_appName}' (GID: '${spacefx_service_userid}') exists..."

            # This will return the group_name for the groupID.  i.e. "702"
            run_a_script "getent group ${spacefx_service_userid}" preexisting_groupid_by_id --ignore_error
            preexisting_groupid_by_id="${preexisting_groupid_by_id%%:*}"

            # This will check if a group exists and gets its ID
            run_a_script "getent group ${spacefx_service_appName}" preexisting_groupid_by_name --ignore_error
            preexisting_groupid_by_name="${preexisting_groupid_by_name%%:*}"


            if [[ -n "${preexisting_groupid_by_name}" ]] && [[ "${preexisting_groupid_by_id}" == "${preexisting_groupid_by_name}" ]]; then
                info_log "...group '${spacefx_service_appName}' (GID: '${preexisting_groupid_by_id}') already exists.  Nothing to do"
            else
                if [[ -n "${preexisting_groupid_by_id}" ]]; then
                    info "...GID '${spacefx_service_userid}' already in use, but isn't assigned to '${spacefx_service_appName}'.  Attempting to delete..."
                    run_a_script "getent group ${spacefx_service_userid}" group_to_del
                    group_to_del="${group_to_del%%:*}"

                    run_a_script "groupdel -f ${group_to_del}"
                    info "...successfully deleted previous group '${group_to_del}' (GID: '${username_to_del}')"
                fi

                if [[ -n "${preexisting_groupid_by_name}" ]]; then
                    info "...Group '${spacefx_service_appName}' already in use, but isn't assigned to '${spacefx_service_userid}'.  Attempting to delete..."
                    run_a_script "groupdel -f ${spacefx_service_appName}"
                    info "...successfully deleted previous group '${spacefx_service_appName}'"
                fi

                info_log "...creating group '${spacefx_service_appName}' with GID '${spacefx_service_userid}'..."
                run_a_script "groupadd -r -g ${spacefx_service_userid} ${spacefx_service_appName}" --no_log
                info_log "...successfully created group '${spacefx_service_appName}' (GID: '${spacefx_service_userid}')."
            fi


            info_log "...checking if user '${spacefx_service_appName}' (UID: '${spacefx_service_userid}') exists..."

            # This will return a user id if the userid exists.  i.e. "701"
            run_a_script "id -u ${spacefx_service_userid}" preexisting_userid --ignore_error

            # This will return the user id for the username.  i.e. "702"
            run_a_script "id -u ${spacefx_service_appName}" preexisting_userid_for_username --ignore_error

            if [[ -n "${preexisting_userid_for_username}" ]] && [[ "${preexisting_userid}" == "${preexisting_userid_for_username}" ]]; then
                info_log "...user '${spacefx_service_appName}' (UID: '${spacefx_service_userid}') already exists.  Nothing to do"
            else
                if [[ -n "${preexisting_userid}" ]]; then
                    info "...UID '${spacefx_service_userid}' already in use, but isn't assigned to '${spacefx_service_appName}'.  Attempting to delete..."
                    run_a_script "getent passwd ${spacefx_service_userid}" username_to_del
                    username_to_del="${username_to_del%%:*}"
                    run_a_script "userdel -f ${username_to_del}"
                    info "...successfully deleted previous user '${username_to_del}' (UID: '${username_to_del}')"
                fi

                if [[ -n "${preexisting_userid_for_username}" ]]; then
                    info "...Username '${spacefx_service_appName}' already in use, but isn't assigned to '${spacefx_service_userid}'.  Attempting to delete..."
                    run_a_script "userdel -f ${spacefx_service_appName}"
                    info "...successfully deleted previous user '${spacefx_service_appName}' (UID: '${preexisting_userid_for_username}')"
                fi

                info_log "...creating user '${spacefx_service_appName}' with UID '${spacefx_service_userid}'..."
                run_a_script "useradd -r -u ${spacefx_service_userid} -g ${spacefx_service_appName} -d /nonexistent -s /usr/sbin/nologin ${spacefx_service_appName}" --no_log
                info_log "...successfully created user '${spacefx_service_appName}' (UID: '${spacefx_service_userid}')."
            fi


        fi



        info_log "...adding '${service}'..."
        deploy_group_cmd="${deploy_group_cmd} --set services.${service_group}.${service}.enabled=true \
                                                --set services.${service_group}.${service}.provisionVolumeClaims=true \
                                                --set services.${service_group}.${service}.provisionVolumes=true"

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

                deploy_group_cmd="${deploy_group_cmd} --set services.${service_group}.${service}.hostDirectoryMounts[${host_directory_mount_count}].name=${mount_name}  \
                                                        --set services.${service_group}.${service}.hostDirectoryMounts[${host_directory_mount_count}].hostPath=${mount_path}"

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
# Copies the app binary to the deployment service
############################################################
function deploy_apps_to_deployment_service(){
    info_log "START: ${FUNCNAME[0]}"

    if [[ ! -d "${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl" ]]; then
        run_a_script "mkdir -p ${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl"
    fi

    if [[ ! -d "${SPACEFX_DIR}/xfer/platform-deployment/tmp/helm" ]]; then
        run_a_script "mkdir -p ${SPACEFX_DIR}/xfer/platform-deployment/tmp/helm"
    fi

    if [[ ! -d "${SPACEFX_DIR}/xfer/platform-deployment/tmp/chart" ]]; then
        run_a_script "mkdir -p ${SPACEFX_DIR}/xfer/platform-deployment/tmp/chart"
    fi

    info_log "Copying '${SPACEFX_DIR}/bin/${ARCHITECTURE}/regctl/${VER_REGCTL}' to '${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl/regctl'..."
    run_a_script "cp ${SPACEFX_DIR}/bin/${ARCHITECTURE}/regctl/${VER_REGCTL}/regctl ${SPACEFX_DIR}/xfer/platform-deployment/tmp/regctl/regctl"
    info_log "...successfully copied regctl binary to '${SPACEFX_DIR}/tmp/platform-deployment/regctl/regctl'"

    info_log "Copying '${SPACEFX_DIR}/bin/${ARCHITECTURE}/helm/${VER_HELM}' to '${SPACEFX_DIR}/xfer/platform-deployment/tmp/helm/helm'..."
    run_a_script "cp ${SPACEFX_DIR}/bin/${ARCHITECTURE}/helm/${VER_HELM}/helm ${SPACEFX_DIR}/xfer/platform-deployment/tmp/helm/helm"
    info_log "...successfully copied helm binary to '${SPACEFX_DIR}/tmp/platform-deployment/helm/helm'"

    info_log "Copying '${SPACEFX_DIR}/chart' to '${SPACEFX_DIR}/xfer/platform-deployment/tmp/chart/${SPACEFX_VERSION}'..."
    run_a_script "cp -r ${SPACEFX_DIR}/chart ${SPACEFX_DIR}/xfer/platform-deployment/tmp/chart/${SPACEFX_VERSION}"
    info_log "...successfully copied chart to '${SPACEFX_DIR}/xfer/platform-deployment/tmp/chart/${SPACEFX_VERSION}'"


    run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.global.security.forceNonRoot' -r" spacefx_forceNonRoot

    if [[ "${spacefx_forceNonRoot}" == "true" ]]; then
        info_log "Updating permissions for '${SPACEFX_DIR}/xfer/platform-deployment' to user 'platform-deployment'..."
        run_a_script "chown -R platform-deployment:platform-deployment ${SPACEFX_DIR}/xfer/platform-deployment"
        run_a_script "chmod -R u+rwx ${SPACEFX_DIR}/xfer/platform-deployment"
        info_log "Permissions successfully updated"
    fi

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
    done < <(find "${SPACEFX_DIR}/yamls" -maxdepth 1 -name "*.yaml")

    info_log "All pre-staged yaml files have been deployed."

    info_log "FINISHED: ${FUNCNAME[0]}"
}


function main() {
    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log DEV_ENVIRONMENT

    if [[ -n "${USER}" ]]; then
        info_log "Updating ownership of ${SPACEFX_DIR}..."
        run_a_script "chown -R ${USER}:${USER} ${SPACEFX_DIR}"
        info_log "...successfully updated ownership of ${SPACEFX_DIR}"
    fi



    check_and_create_certificate_authority

    info_log "Deploying k3s..."
    run_a_script "${SPACEFX_DIR}/scripts/deploy/deploy_k3s.sh"
    info_log "...successfully deployed k3s"

    deploy_namespaces

    run_a_script "${SPACEFX_DIR}/scripts/coresvc_registry.sh --start"
    run_a_script "${SPACEFX_DIR}/scripts/deploy/deploy_chart_dependencies.sh"

    [[ "${DEV_ENVIRONMENT}" == false  ]] && run_a_script "${SPACEFX_DIR}/scripts/deploy/build_service_images.sh"

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

    deploy_apps_to_deployment_service
    deploy_prestaged_yamls


    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main