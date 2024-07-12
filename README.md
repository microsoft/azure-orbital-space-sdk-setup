# Azure Orbital Space SDK - Setup

[![spacefx-dev-build-publish](https://github.com/microsoft/azure-orbital-space-sdk-setup/actions/workflows/devcontainer-feature-build-publish.yml/badge.svg)](https://github.com/microsoft/azure-orbital-space-sdk-setup/actions/workflows/devcontainer-feature-build-publish.yml)

This repository hosts the configuration and scripts to used to deploy the Azure Orbital Space SDK to an environment (including DevContainer and host environment). These are components to be mixed-and-matched to achieve the desired state, and are intended to be centralized to accelerate new deployments and configurations.

## Deployment
Deploying the Microsoft Azure Orbital Space SDK is done one of two ways: Production and Development.

### Production Deployment
Production deploments are intended to run on a satellite with an emphasis on reduced size and reduced logging.  Follow the below steps to deploy the production configuration

1.  Stage the artifacts and containers for the Microsoft Azure Orbital Space SDK
    ```bash
    # Clone the repo
    git clone https://github.com/microsoft/azure-orbital-space-sdk-setup
    cd ./azure-orbital-space-sdk-setup

    # Initialize /var/spacedev
    ./.vscode/copy_to_spacedev.sh

    # Stage all the artifacts and containers
    /var/spacedev/scripts/stage_spacefx.sh

    # Or specify the architecture to download a different architecture
    /var/spacedev/scripts/stage_spacefx.sh --architecture arm64

    # Create a clean output directory
    sudo mkdir -p ./output && sudo rm -rf ./output/*
    sudo tar -czf ./output/msft_azure_orbital_space_sdk.tar.gz -C /var/spacedev .
    ```

1.  Copy the `./output/msft_azure_orbital_space_sdk.tar.gz` to the target hardware / satellite / host

1.  Deploy the Microsoft Azure Orbital Space SDK
    ```bash
    # Extract the Microsoft Azure Orbital Space SDK to /var/spacedev
    sudo mkdir -p /var/spacedev
    sudo chown -R "${USER:-$(id -un)}" /var/spacedev
    sudo tar -xzvf msft_azure_orbital_space_sdk.tar.gz -C /var/spacedev

    # Deploy the Microsoft Azure Orbital Space SDK
    /var/spacedev/scripts/deploy_spacefx.sh
    ```

### Developmnt
Development deploments are intended to experiment and develop a payload application / plugin with an emphasis on accelerated deployment and more logging.  Follow the below steps to deploy the development configuration

TODO: Add steps to include the feature


## Testing
Test scripts for the Microsoft Azure Orbital Space SDK are available at [./tests](https://github.com/microsoft/azure-orbital-space-sdk-setup/tree/main/tests).  The scripts are atomic and idempotent; they are intended to be run on a host from within this repository.  Successful test will have a zero (0) exit code; failed tests will return a non-zero exit code.  Example a successful test:

```bash
spacecowboy@spacedev-vm:~/azure-orbital-space-sdk-setup$ ./tests/prod_cluster.sh
...
// output abbreviated //
...
-------------------------------
prod_cluster.sh - Test successful

spacecowboy@spacedev-vm:~/azure-orbital-space-sdk-setup$ echo $?
0
```

```bash
spacecowboy@spacedev-vm:~/azure-orbital-space-sdk-setup$ ./tests/dev_cluster.sh
...
// output abbreviated //
...
-------------------------------
dev_cluster.sh - Test successful

spacecowboy@spacedev-vm:~/azure-orbital-space-sdk-setup$ echo $?
0
```

## Building prerequisite container images
Several container images are used as components within the Azure Orbital Space SDK.  This container images are used as utilies for gpu tests, intermediate layers to reduce the filesize of apps to deploy, etc.  These prerequisite container images are prebuilt and available in this repo and will be downloaded during stage_spacefx.sh depending on the options provided.  There is no need to manually build these container images, but their build process is documented for reference.
```bash
# Load the configuration and get the channel for the tag
source /var/spacedev/env/spacefx.env
SPACEFX_VERSION_CHANNEL_TAG="${SPACEFX_VERSION}"
[[ "${SPACEFX_CHANNEL}" != "stable" ]] && SPACEFX_VERSION_CHANNEL_TAG="${SPACEFX_VERSION}-${SPACEFX_CHANNEL}"
CPU_ARCHITECTURE=$(uname -m)
[[ "${CPU_ARCHITECTURE}" == "aarch64" ]] && CPU_ARCHITECTURE="arm64"
[[ "${CPU_ARCHITECTURE}" == "x86_64" ]] && CPU_ARCHITECTURE="amd64"

# SpaceSDK-Base Container image build
/var/spacedev/build/build_containerImage.sh \
    --dockerfile /var/spacedev/build/spacesdk-base/Dockerfile.spacesdk-base \
    --image-tag ${SPACEFX_VERSION} \
    --repo-dir ${PWD} \
    --app-name spacesdk-base \
    --annotation-config azure-orbital-space-sdk-core.yaml


# Python-Base and SpaceSDK-Base-Python Container image build
PYTHON_VERSIONS=("3.10" "3.9")
for i in "${!PYTHON_VERSIONS[@]}"; do
    PYTHON_VERSION=${PYTHON_VERSIONS[i]}
    PYTHON_VERSION_TAG_CHANNEL=${PYTHON_VERSION}
    [[ "${SPACEFX_CHANNEL}" != "stable" ]] && PYTHON_VERSION_TAG_CHANNEL="${PYTHON_VERSION_TAG_CHANNEL}-${SPACEFX_CHANNEL}"

    # Build and push Python-Base images.  This is an intermediate layer with only Python (built from source)
    /var/spacedev/build/build_containerImage.sh \
        --dockerfile /var/spacedev/build/python/Dockerfile.python-base \
        --image-tag ${PYTHON_VERSION} \
        --repo-dir ${PWD} \
        --no-spacefx-dev \
        --app-name python-base \
        --build-arg PYTHON_VERSION="${PYTHON_VERSION}" \
        --annotation-config azure-orbital-space-sdk-core.yaml

    # Build spacesdk-python-base, which is a combination of spacesdk-base and python-base
    /var/spacedev/build/build_containerImage.sh \
        --dockerfile /var/spacedev/build/python/Dockerfile.python-spacesdk-base \
        --image-tag 0.11.0_${PYTHON_VERSION} \
        --repo-dir ${PWD} \
        --no-spacefx-dev \
        --app-name spacesdk-base-python \
        --build-arg PYTHON_VERSION="${PYTHON_VERSION_TAG_CHANNEL}" \
        --build-arg SDK_VERSION="${SPACEFX_VERSION_CHANNEL_TAG}" \
        --annotation-config azure-orbital-space-sdk-core.yaml

done


# Build the SpaceSDK-Jetson-DeviceQuery Versions
CUDA_VERSIONS=("11.4" "12.2")
for i in "${!CUDA_VERSIONS[@]}"; do
    CUDA_VERSION=${CUDA_VERSIONS[i]}
    /var/spacedev/build/build_containerImage.sh \
        --dockerfile /var/spacedev/build/gpu/jetson/Dockerfile.deviceQuery \
        --build-arg CUDA_VERSION="${CUDA_VERSION}" \
        --image-tag "cuda-${CUDA_VERSION}" \
        --repo-dir ${PWD} \
        --no-spacefx-dev \
        --app-name spacesdk-jetson-devicequery \
        --annotation-config azure-orbital-space-sdk-core.yaml

    /var/spacedev/build/build_containerImage.sh \
        --dockerfile /var/spacedev/build/gpu/jetson/Dockerfile.deviceQuery.dev \
        --build-arg CUDA_VERSION="${CUDA_VERSION}" \
        --image-tag "cuda-${CUDA_VERSION}-dev" \
        --repo-dir ${PWD} \
        --no-spacefx-dev \
        --app-name spacesdk-jetson-devicequery \
        --annotation-config azure-orbital-space-sdk-core.yaml
done


docker build \
--build-arg L4T_VERSION=nvcr.io/nvidia/l4t-ml:r36.2.0-py3 \
--build-arg ONNXRUNTIME_REPO=https://github.com/microsoft/onnxruntime \
--build-arg ONNXRUNTIME_COMMIT=v1.18.1 \
--build-arg BUILD_CONFIG=Release \
--build-arg CMAKE_VERSION=3.28.1 \
--build-arg CPU_ARCHITECTURE=aarch64 \
--build-arg CUDA_ARCHITECTURES="70;72;75;80;86;87" \
-t onnx-builder \
-f /home/ryan/azure-orbital-space-sdk-setup/build/gpu/jetson/Dockerfile.onnxruntime_gpu .

docker run --name=onnx-builder --rm  -v /var/spacedev:/var/spacedev onnx-builder:latest busybox cp /output /var/spacedev/tmp/onnxruntime_gpu -r

/var/spacedev/build/push_build_artifact.sh \
        --artifact /var/spacedev/wheel/microsoftazurespacefx/onnxruntime_gpu-1.16.3-cp38-cp38-linux_aarch64.whl \
        --annotation-config azure-orbital-space-sdk-core.yaml \
        --architecture ${CPU_ARCHITECTURE} \
        --artifact-version 0.11.0


```

## Building the Microsoft Azure Orbital DevContainer Feature
Microsoft Azure Orbital Space SDK is centrally deployed by a custom devcontainer feature.

### Install devcontainer CLI
```bash
sudo apt install npm
sudo npm cache clean -f
sudo npm install -g n
sudo n stable
sudo npm install -g @devcontainers/cli
```

### Build devcontainer feature
```bash
REGISTRY=ghcr.io/microsoft
VERSION=0.11.0

# No other changes needed below this line
FEATURE=azure-orbital-space-sdk/spacefx-dev
ARTIFACT_PATH=./output/spacefx-dev/devcontainer-feature-spacefx-dev.tgz

# Validate the output directory exists and clean it out if there is content already present
[[ -d ./output/spacefx-dev ]]; sudo rm ./output/spacefx-dev/* -rf

# Copy the scripts ino the entry point for the devcontainer feature
./.vscode/copy_to_spacedev.sh --output-dir ./.devcontainer/features/spacefx-dev/azure-orbital-space-sdk-setup

# Build the devcontainer feature
devcontainer features package --force-clean-output-folder ./.devcontainer/features --output-folder ./output/spacefx-dev

# Push the devcontainer feature tarball to the registry
oras push ${REGISTRY}/${FEATURE}:${VERSION} \
    --config /dev/null:application/vnd.devcontainers \
    --annotation org.opencontainers.image.source=https://github.com/microsoft/azure-orbital-space-sdk-setup \
            ${ARTIFACT_PATH}:application/vnd.devcontainers.layer.v1+tar


```

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft
trademarks or logos is subject to and must follow
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
