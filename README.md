# Azure Orbital Space SDK - Setup



## Build and Deploying DevContainer Feature

This devcontainer feature can be built and deployed using the devcontainer CLI.

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
mkdir -p "./output/spacefx-dev"
[[ -f ./output/spacefx-dev/* ]]; rm ./output/spacefx-dev/*

# Copy the scripts ino the entry point for the devcontainer feature
./.vscode/copy_to_spacedev.sh --output_dir ./.devcontainer/features/spacefx-dev/azure-orbital-space-sdk-setup

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
