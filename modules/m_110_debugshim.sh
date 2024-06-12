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

    run_a_script "kubectl get persistentvolumeclaim --output json -A | jq -r '.items[] | select(.metadata.labels.\"microsoft.azureorbital/appName\" == \"${appId}\") | {pvc_name: .metadata.name, pvc_namespace: .metadata.namespace} | @base64'" pvcs

    for pvc in $pvcs; do
        parse_json_line --json "${pvc}" --property ".pvc_name" --result pvc_name
        parse_json_line --json "${pvc}" --property ".pvc_namespace" --result pvc_namespace
        debug_log "Deleting PVC '${pvc_name}' from namespace '${pvc_namespace}'..."
        run_a_script "kubectl delete persistentvolumeclaim/${pvc_name} -n ${pvc_namespace} --now=true"
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
    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get pods --field-selector=status.phase=Running -A" k3s_deployments --ignore_error

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