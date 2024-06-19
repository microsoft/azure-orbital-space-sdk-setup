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

echo "Microsoft Azure Orbital Space SDK - Production Cluster Test"

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

kubectl get deployment/coresvc-registry -n coresvc
kubectl get deployment/coresvc-fileserver -n coresvc
kubectl get deployment/coresvc-switchboard -n coresvc

kubectl get deployment/hostsvc-link -n hostsvc
kubectl get deployment/hostsvc-sensor -n hostsvc
kubectl get deployment/hostsvc-logging -n hostsvc
kubectl get deployment/hostsvc-position -n hostsvc


kubectl get deployment/platform-deployment -n platformsvc
kubectl get deployment/platform-mts -n platformsvc

echo ""
echo ""
echo ""
echo "-------------------------------"
echo "${SCRIPT_NAME} - Test successful"
set +e