#!/bin/bash
#
#  Deploys and tests the cluster in it's development configuration
#

# Example Usage:
#
#  "bash ./tests/dev_cluster.sh"
set -e
SCRIPT_NAME=$(basename "$0")
echo "Microsoft Azure Orbital Space SDK - Development Cluster Test"

if [[ -d "/var/spacedev" ]]; then
    echo "Preexisting /var/spacedev found.  Resetting enviornment with big_red_button.sh"
    /var/spacedev/scripts/big_red_button.sh
fi

# There's some containers already running.  Reset the environment
if docker ps -q | grep -q .; then
    echo "Preexisting containers found.  Resetting enviornment with big_red_button.sh"
    /var/spacedev/scripts/big_red_button.sh
fi

./.vscode/copy_to_spacedev.sh

echo "Provisioning devcontainer"
devcontainer up --workspace-folder "${PWD}" --workspace-mount-consistency cached --id-label devcontainer.local_folder="${PWD}" --default-user-env-probe loginInteractiveShell --build-no-cache --remove-existing-container --mount type=volume,source=vscode,target=/vscode,external=true --update-remote-user-uid-default on --mount-workspace-git-root true

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
kubectl get deployment/vth -n platformsvc


echo ""
echo ""
echo ""
echo "-------------------------------"
echo "${SCRIPT_NAME} - Test successful"
set +e