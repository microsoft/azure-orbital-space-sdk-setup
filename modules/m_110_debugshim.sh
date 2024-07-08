#!/bin/bash

############################################################
# Remove deployment by its app id across all namespaces
############################################################
function remove_deployment_by_app_id() {
    info_log "START: ${FUNCNAME[0]}"

    local appId=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --app_id)
            shift
            appId=$1
            ;;
        esac
        shift
    done

    [[ -z "${appId}" ]] && exit_with_error "--app_id is required for remove_deployment_by_app_id function"

    debug_log "Removing previous deployments for '${appId}'..."

    run_a_script "kubectl get deployments -A -o json | jq -r '.items[] | select(.metadata.labels.\"microsoft.azureorbital/appName\" == \"${appId}\") | {deployment: .metadata.name, namespace: .metadata.namespace} | @base64'" deployments

    for deployment in $deployments; do
        parse_json_line --json "${deployment}" --property ".deployment" --result deployment_name
        parse_json_line --json "${deployment}" --property ".namespace" --result deployment_namespace
        debug_log "Stopping deployment '${deployment_name}' in namespace '${deployment_namespace}'..."
        run_a_script "kubectl delete deployment/${deployment_name} -n ${deployment_namespace} --now=true"
    done

    debug_log "...all previous deployments removed for '${appId}'"

    debug_log "Removing volume claims for '${appId}'..."

    run_a_script "kubectl get persistentvolumeclaim --output json -A | jq -r '.items[] | select(.metadata.labels.\"microsoft.azureorbital/appName\" == \"${appId}\") | {pvc_name: .metadata.name, pvc_namespace: .metadata.namespace, volume_name: .spec.volumeName} | @base64'" pvcs

    for pvc in $pvcs; do
        parse_json_line --json "${pvc}" --property ".pvc_name" --result pvc_name
        parse_json_line --json "${pvc}" --property ".volume_name" --result volume_name
        parse_json_line --json "${pvc}" --property ".pvc_namespace" --result pvc_namespace
        debug_log "Deleting PVC '${pvc_name}' from namespace '${pvc_namespace}'..."
        run_a_script "kubectl delete persistentvolumeclaim/${pvc_name} -n ${pvc_namespace} --now=true"
        run_a_script "kubectl delete persistentvolume/${volume_name} --now=true"
    done

    debug_log "...all volume claims for '${appId}' have been removed"

    info_log "END: ${FUNCNAME[0]}"
}



############################################################
# Wait for pods to terminate and get removed by their app id
############################################################
function wait_for_deployment_deletion_by_app_id() {
    info_log "START: ${FUNCNAME[0]}"

    local appId=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --app_id)
            shift
            appId=$1
            ;;
        esac
        shift
    done

    [[ -z "${appId}" ]] && exit_with_error "--app_id is required for remove_deployment_by_app_id function"

    local pods_cleaned
    pods_cleaned=false
    start_time=$(date +%s)

    # This returns any pods that are running
    run_a_script "kubectl get pods --field-selector=status.phase=Running -A" k3s_deployments --ignore_error

    # This loops and waits for at least 1 pod to flip the running
    while [[ ${pods_cleaned} == false ]]; do

        # Letting the pods be terminating status is sufficent for this step
        run_a_script "kubectl get deployments -A --output json -l \"microsoft.azureorbital/appName\"=\"${appId}\" | jq -r '.items | length '" num_of_deployments
        run_a_script "kubectl get persistentvolumeclaim --output json -A -l \"microsoft.azureorbital/appName\"=\"${appId}\" | jq -r '.items | length'" num_of_volumes

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for pods to finish terminating.  Check if an error has happened and retry"
        fi

        if [[ "${num_of_deployments}" == "0" ]] && [[ "${num_of_volumes}" == "0" ]]; then
            info_log "...no deployments, pods, nor volumes detected"
            pods_cleaned=true
        else
            info_log "...waiting for cleanup (deployments: ${num_of_deployments}, pods: ${num_of_pods}, volumes: ${num_of_volumes})..."
            sleep 0.5
        fi
    done

    info_log "Pods and volumes successfully terminated for '${appId}'."

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Check for python and update the environment if found
############################################################
function _check_for_python() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Checking for python..."


    is_cmd_available "python" has_cmd
    if [[ "${has_cmd}" == false ]]; then
        info_log "Python not found.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    if [[ "${APP_TYPE}" != "payloadapp" ]] && [[ "${APP_TYPE}" != "spacesdk-client" ]]; then
        info_log "Python found, but APP_TYPE of '${APP_TYPE}' is not 'payloadapp' nor 'spacesdk-client'.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    if [[ "${DEV_LANGUAGE}" != "python" ]]; then
        info_log "Python found, but DEV_LANGUAGE of '${DEV_LANGUAGE}' is not 'python'.  Nothing to do."
        info_log "END: ${FUNCNAME[0]}"
        return
    fi


    info_log "Python found.  Updating environment with dependencies..."
    debug_log "...adding socat and nuget to EXTRA_PACKAGES..."
    EXTRA_PACKAGES+=("socat")
    EXTRA_PACKAGES+=("nuget")

    # Add DEV_PYTHON to app.env so apps downstream can use it
    run_a_script "tee -a ${SPACEFX_DEV_ENV} > /dev/null << SPACEFX_UPDATE_END
export DEV_PYTHON=true
SPACEFX_UPDATE_END" --disable_log

    run_a_script "tee -a  /spacefx-dev/config/dev_python > /dev/null << SPACEFX_UPDATE_END
true
SPACEFX_UPDATE_END" --disable_log

    source "${SPACEFX_DEV_ENV}"

    info_log "Successfully updated environment with Python dependencies."
    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Automatically add options to download for debug shims
############################################################
function _auto_add_downloads() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Adding downloads and artifacts for APP_TYPE '${APP_TYPE}'..."

    calculate_tag_from_channel --tag "${SPACEFX_VERSION}_base" --result _auto_add_tag_spacefx_tag

    case "${APP_TYPE}" in
        "sdk-service")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            ;;
        "hostsvc-position-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.HostServices.Position.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("hostsvc-position:${_auto_add_tag_spacefx_tag}")
            ;;
        "hostsvc-sensor-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.HostServices.Sensor.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("hostsvc-sensor:${_auto_add_tag_spacefx_tag}")
            ;;
        "hostsvc-logging-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.HostServices.Logging.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("hostsvc-logging:${_auto_add_tag_spacefx_tag}")
            ;;
        "hostsvc-link-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.HostServices.Link.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("hostsvc-link:${_auto_add_tag_spacefx_tag}")
            ;;
        "platform-mts-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.PlatformServices.MessageTranslationService.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("platform-mts:${_auto_add_tag_spacefx_tag}")
            ;;
        "platform-deployment-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.PlatformServices.Deployment.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("platform-deployment:${_auto_add_tag_spacefx_tag}")
            ;;
        "vth-plugin")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.VTH.Plugins.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("vth:${_auto_add_tag_spacefx_tag}")
            ;;
        "spacesdk-client")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            PULL_CONTAINERS+=("vth:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("platform-deployment:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("platform-mts:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-link:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-sensor:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-position:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-logging:${_auto_add_tag_spacefx_tag}")
            ;;
        "payloadapp")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Core.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("Microsoft.Azure.SpaceSDK.Client.${SPACEFX_VERSION}.nupkg")
            DOWNLOAD_ARTIFACTS+=("microsoftazurespacefx-${SPACEFX_VERSION}-py3-none-any.whl")
            PULL_CONTAINERS+=("vth:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("platform-deployment:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("platform-mts:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-link:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-sensor:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-position:${_auto_add_tag_spacefx_tag}")
            PULL_CONTAINERS+=("hostsvc-logging:${_auto_add_tag_spacefx_tag}")
            ;;
    esac

    debug_log "Artifacts queued to download:"
    for i in "${!DOWNLOAD_ARTIFACTS[@]}"; do
        DOWNLOAD_ARTIFACT=${DOWNLOAD_ARTIFACTS[i]}
        debug_log "...Artifact: ${DOWNLOAD_ARTIFACT}"
    done

    debug_log "Containers queued to download:"
    for i in "${!PULL_CONTAINERS[@]}"; do
        PULL_CONTAINER=${PULL_CONTAINERS[i]}
        debug_log "...Container: ${PULL_CONTAINER}"
    done


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Compile any of the protos found
############################################################
function python_compile_protos() {
    info_log "START: ${FUNCNAME[0]}"

    # Building the .protos directory
    create_directory "${CONTAINER_WORKING_DIR:?}/.protos"

    info_log "Compiling protos from '${SPACEFX_DIR}/protos/spacefx'..."
    run_a_script "find ${SPACEFX_DIR}/protos/spacefx -iname '*.proto' -type f" protos_found

    for proto in $protos_found; do
        info_log "Compiling proto '${proto}' to '${CONTAINER_WORKING_DIR:?}'..."
        run_a_script "python -m grpc_tools.protoc ${proto} -I=${SPACEFX_DIR}/protos --python_out=${CONTAINER_WORKING_DIR:?}/.protos --grpc_python_out=${CONTAINER_WORKING_DIR:?}/.protos"
        info_log "...successfully compiled proto '${proto}' to '${CONTAINER_WORKING_DIR:?}/.protos'..."
    done
    info_log "...successfully compiled protos from '${SPACEFX_DIR}/protos/spacefx'"

    info_log "Compiling protos from '${CONTAINER_WORKING_DIR:?}/.protos'..."
    run_a_script "find ${CONTAINER_WORKING_DIR:?}/.protos -iname '*.proto' -type f" protos_found

    for proto in $protos_found; do
        info_log "Compiling proto '${proto}' to '${CONTAINER_WORKING_DIR:?}'..."
        run_a_script "python -m grpc_tools.protoc ${proto} -I=${CONTAINER_WORKING_DIR:?}/.protos --python_out=${CONTAINER_WORKING_DIR:?}/.protos --grpc_python_out=${CONTAINER_WORKING_DIR:?}/.protos"
        info_log "...successfully compiled proto '${proto}' to '${CONTAINER_WORKING_DIR:?}/.protos'..."
    done
    info_log "...successfully compiled protos from '${CONTAINER_WORKING_DIR:?}/.protos'"


    info_log "Adding __init__.py to directories..."
    run_a_script "find ${CONTAINER_WORKING_DIR:?}/.protos -type d" proto_dirs

    for proto_dir in $proto_dirs; do
        info_log "Checking for '${proto_dir}/__init__.py'..."
        if [[ ! -f "${proto_dir}/__init__.py" ]]; then
            info_log "...'${proto_dir}/__init__.py' not found.  Adding..."
            run_a_script "touch ${proto_dir}/__init__.py"
            info_log "...successfully added '${proto_dir}/__init__.py'"
        else
            info_log "...'${proto_dir}/__init__.py' found."
        fi
    done

    info_log "...successfully added __init__.py to directories."
}