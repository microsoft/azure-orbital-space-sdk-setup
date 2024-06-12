#!/bin/bash
#
#  Deploys and tests the cluster in it's development configuration
#

# Example Usage:
#
#  "bash ./tests/dev_cluster.sh"
set -e

echo "Microsoft Azure Orbital Space SDK - Development Cluster Test"

if [[ -d "/var/spacedev" ]]; then
    echo "Preexisting /var/spacedev found.  Resetting enviornment with big_red_button.sh"
    /var/spacedev/scripts/big_red_button.sh
fi

# There's some containers already running.  Reset the environment
if docker ps -q | grep -q .; then
    echo "Preexisting containers found.  Resetting enviornment with big_red_button.sh"
    ./.vscode/copy_to_spacedev.sh
    /var/spacedev/scripts/big_red_button.sh
fi

echo "Provisioning devcontainer"
devcontainer up --workspace-folder "${PWD}"

echo "Checking cluster..."
kubectl get deployment/coresvc-registry -n coresvc
kubectl get deployment/coresvc-fileserver -n coresvc
kubectl get deployment/coresvc-switchboard -n coresvc
echo ""
echo ""
echo ""
echo "-------------------------------"
echo "Test successful"
set +e