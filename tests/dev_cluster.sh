#!/bin/bash
#
#  Deploys and tests the cluster in it's development configuration
#

# Example Usage:
#
#  "bash ./tests/dev_cluster.sh"
set -e
MAX_WAIT_SECS=300
SCRIPT_NAME=$(basename "$0")
WORKING_DIR="$(git rev-parse --show-toplevel)"

# Test setups for the devcontainer feature to push to
REGISTRY=ghcr.io/microsoft
VERSION=0.11.0_test_do_not_use

# No other changes needed below this line
FEATURE=azure-orbital-space-sdk/spacefx-dev
ARTIFACT_PATH=${WORKING_DIR}/output/spacefx-dev/devcontainer-feature-spacefx-dev.tgz



echo "Microsoft Azure Orbital Space SDK - Development Cluster Test"

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
    echo "Preexisting /var/spacedev found.  Resetting enviornment with big_red_button.sh"
    /var/spacedev/scripts/big_red_button.sh
fi

# There's some containers already running.  Reset the environment
if docker ps -q | grep -q .; then
    echo "Preexisting containers found.  Resetting enviornment with big_red_button.sh"
    # There may be containers that aren't part of Space SDK.  Copy files so we can run big_red_button.sh
    ./.vscode/copy_to_spacedev.sh
    /var/spacedev/scripts/big_red_button.sh
fi


has_devcontainer_cli=$(whereis -b "devcontainer")

if [[ $has_devcontainer_cli == "devcontainer:" ]]; then
    echo "The 'devcontainer' command is not available.  Please install it and retry."
    exit 1
fi

has_oras=$(whereis -b "oras")

if [[ $has_oras == "oras:" ]]; then
    echo "The 'oras' command is not available.  Please install it and retry."
    exit 1
fi

echo "Building the devcontainer feature '${REGISTRY}/${FEATURE}:${VERSION}'..."


echo "...cleaning out output directory..."
[[ -d ./output/spacefx-dev ]] && sudo rm ./output/spacefx-dev/* -rf

echo "...running copy_to_spacedev.sh"
# Copy the scripts ino the entry point for the devcontainer feature
${WORKING_DIR}/.vscode/copy_to_spacedev.sh --output-dir ${WORKING_DIR}/.devcontainer/features/spacefx-dev/azure-orbital-space-sdk-setup

source ${WORKING_DIR}/.devcontainer/features/spacefx-dev/azure-orbital-space-sdk-setup/env/spacefx.env
 [[ "${SPACEFX_CHANNEL}" != "stable" ]] && VERSION="${VERSION}-${SPACEFX_CHANNEL}"

echo "...building the devcontainer feature..."
# Build the devcontainer feature
devcontainer features package --force-clean-output-folder ${WORKING_DIR}/.devcontainer/features --output-folder ${WORKING_DIR}/output/spacefx-dev


echo "Pushing the devcontainer feature '${REGISTRY}/${FEATURE}:${VERSION}'..."
# Push the devcontainer feature tarball to the registry
oras push --disable-path-validation ${REGISTRY}/${FEATURE}:${VERSION} \
    --config /dev/null:application/vnd.devcontainers \
    --annotation org.opencontainers.image.source=https://github.com/microsoft/azure-orbital-space-sdk-setup \
            ${ARTIFACT_PATH}:application/vnd.devcontainers.layer.v1+tar


echo "Staging /var/spacedev directory..."
${WORKING_DIR}/.vscode/copy_to_spacedev.sh

echo "Provisioning devcontainer with test-feature/devcontainer.json..."
devcontainer up --workspace-folder "${PWD}" \
        --workspace-mount-consistency cached \
        --id-label devcontainer.local_folder="${PWD}" \
        --default-user-env-probe loginInteractiveShell \
        --build-no-cache \
        --remove-existing-container \
        --mount type=volume,source=vscode,target=/vscode,external=true \
        --update-remote-user-uid-default on \
        --mount-workspace-git-root true \
        --override-config "${WORKING_DIR}/.devcontainer/test-feature/devcontainer.json"

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
kubectl --kubeconfig ${KUBECONFIG} get deployment/vth -n platformsvc

wait_for_namespace_to_provision --namespace coresvc
wait_for_namespace_to_provision --namespace hostsvc
wait_for_namespace_to_provision --namespace platformsvc

echo "Checking for artifacts.yaml in /var/spacedev/config..."
artifact_yaml="/var/spacedev/config/artifacts.yaml"
if [[ ! -f "${artifact_yaml}" ]]; then
    echo "artifacts.yaml not found in /var/spacedev/config. Please ensure the file is present."
    exit 1
fi

echo ""
echo ""
echo ""
echo "-------------------------------"
echo "${SCRIPT_NAME} - Test successful"
set +e