REGISTRY=ghcr.io/microsoft
VERSION="0.11.0_${USER}_test"

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