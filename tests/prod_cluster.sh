#!/bin/bash
#
#  Deploys and tests the cluster in it's production configuration
#

# Example Usage:
#
#  "bash ./tests/prod_cluster.sh"
set -e
SCRIPT_NAME=$(basename "$0")
WORKING_DIR="$(git rev-parse --show-toplevel)"
MAX_WAIT_SECS=300
echo "Microsoft Azure Orbital Space SDK - Production Cluster Test"


############################################################
# Given a namespace, this function will wait for all pods to enter a running state
############################################################
function wait_for_namespace_to_provision(){

    local namespace=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --namespace)
                shift
                namespace=$1
                ;;
        esac
        shift
    done

    if [[ -z $namespace ]]; then
        echo "--namespace not provided to wait_for_namespace_to_provision function"
        exit 1
    fi

    echo "Waiting for namespace '${namespace}' to fully provision (max $MAX_WAIT_SECS seconds)..."

    # This returns any pods that are not completed nor succeeded
    k3s_deployments_not_ready=$(kubectl get deployments --kubeconfig "${KUBECONFIG}" -n "${namespace}" --output=json | jq '[.items[] | select(.spec.replicas != .status.availableReplicas)] | length')

    start_time=$(date +%s)

    while [[ $k3s_deployments_not_ready != "0" ]]; do
        k3s_deployments_not_ready=$(kubectl get deployments --kubeconfig "${KUBECONFIG}" -n "${namespace}" --output=json | jq '[.items[] | select(.spec.replicas != .status.availableReplicas)] | length')

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            echo "Timed out waiting for deployment to complete.  Check logs for more information"
            exit 1
        fi

        kubectl get pods -A
        kubectl get deployments -A

        echo "Found incomplete deployments.  Rechecking in 5 seconds"
        sleep 5
    done

    echo "Namespace '${namespace}' is provisioned"

}

if [[ -d "/var/spacedev" ]]; then
    echo "Resetting enviornment with big_red_button.sh"
    /var/spacedev/scripts/big_red_button.sh
fi

echo "Creating /var/spacedev directory..."
${WORKING_DIR}/.vscode/copy_to_spacedev.sh


echo "Staging Microsoft Azure Orbital Space SDK..."
/var/spacedev/scripts/stage_spacefx.sh

echo "Deploying Microsoft Azure Orbital Space SDK..."
/var/spacedev/scripts/deploy_spacefx.sh

echo "Checking cluster..."
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
if [[ ! -f "${KUBECONFIG}" ]]; then
    echo "KUBECONFIG '${KUBECONFIG}' not found.  Cluster did not initialize."
    exit 1
fi

kubectl --kubeconfig ${KUBECONFIG} get deployment/coresvc-registry -n coresvc
kubectl --kubeconfig ${KUBECONFIG} get deployment/coresvc-switchboard -n coresvc

kubectl --kubeconfig ${KUBECONFIG} get deployment/hostsvc-link -n hostsvc
kubectl --kubeconfig ${KUBECONFIG} get deployment/hostsvc-sensor -n hostsvc
kubectl --kubeconfig ${KUBECONFIG} get deployment/hostsvc-logging -n hostsvc
kubectl --kubeconfig ${KUBECONFIG} get deployment/hostsvc-position -n hostsvc


kubectl --kubeconfig ${KUBECONFIG} get deployment/platform-deployment -n platformsvc
kubectl --kubeconfig ${KUBECONFIG} get deployment/platform-mts -n platformsvc


wait_for_namespace_to_provision --namespace coresvc
wait_for_namespace_to_provision --namespace hostsvc
wait_for_namespace_to_provision --namespace platformsvc


echo ""
echo ""
echo ""
echo "-------------------------------"
echo "${SCRIPT_NAME} - Test successful"
set +e