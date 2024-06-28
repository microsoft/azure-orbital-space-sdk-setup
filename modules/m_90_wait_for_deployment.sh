#!/bin/bash

############################################################
# Waits for a deployment to finish in kubernetes
############################################################
function wait_for_deployment() {
    local namespace=""
    local deployment=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --deployment)
                shift
                deployment=$1
                ;;
            --namespace)
                shift
                namespace=$1
                ;;
        esac
        shift
    done

    if [[ -z "${deployment}" ]]; then
        exit_with_error "--deployment parameter is required for wait_for_deployment function"
    fi

    if [[ -z "${namespace}" ]]; then
        exit_with_error "--namespace parameter is required for wait_for_deployment function"
    fi

    start_time=$(date +%s)

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployment -n ${namespace} ${deployment} -o=json | jq 'any(.status.conditions[]; .type==\"Available\" and .status==\"True\")'" deployment_status --ignore_error

    # kubectl may error, especially if the cluster is booting up.  Setting it to false lets us continue the loop and let the cluster finish coming online
    [[ -z "${deployment_status}" ]] && deployment_status=false

    start_time=$(date +%s)

    # This loops and waits for at least 1 pod to flip the running
    while [[ "${deployment_status}" != true ]]; do
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get deployment -n ${namespace} ${deployment} -o=json | jq 'any(.status.conditions[]; .type==\"Available\" and .status==\"True\")'" deployment_status --ignore_error

        # kubectl may error, especially if the cluster is booting up.  Setting it to false lets us continue the loop and let the cluster finish coming online
        [[ -z "${deployment_status}" ]] && deployment_status=false

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for ${deployment} to finish deploying.  Check for errors"
        fi

        info_log "...Deployment '${namespace} / ${deployment}' is not available yet.  Rechecking in 2 seconds..."
        sleep 2
    done

}