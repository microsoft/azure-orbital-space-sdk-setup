#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/azure-orbital-space-sdk-setup/README.md

export DEBIAN_FRONTEND=noninteractive

# Only run as the root user
if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Setup the directory on the host so we can copy our files over to it
set -e

# If we're running in the devcontainer with the k3s-on-host feature, source the .env file
[[ -f "/devfeature/k3s-on-host/.env" ]] && source /devfeature/k3s-on-host/.env

# Pull in the app.env file built by the feature
[[ -f "/spacefx-dev/app.env" ]] && source /spacefx-dev/app.env

## Create the spacefx-dev directory on the host if it doesn't exist
[[ ! -d "${SPACEFX_DIR_FOR_HOST:?}" ]] && mkdir -p "${SPACEFX_DIR_FOR_HOST:?}"

## Create a symlink on the devcontainer to the host directory so the directory paths match on both
[[ ! -L "${SPACEFX_DIR}" ]] && ln -s "${SPACEFX_DIR_FOR_HOST:?}" "${SPACEFX_DIR:?}"

## Provision the spacefx-dev directory with the latest files from spacesdk-setup
cp /azure-orbital-space-sdk-setup/* "${SPACEFX_DIR_FOR_HOST:?}" -r
set +e


source "${SPACEFX_DIR:?}/modules/load_modules.sh" $@ --log_dir "${SPACEFX_DIR:?}/logs/${APP_NAME:?}"


function main() {
    if [[ "${CLUSTER_ENABLED}" == "false" ]]; then
        return
    fi

    run_a_script_on_host "${SPACEFX_DIR}/scripts/stage_spacefx.sh"
    run_a_script_on_host "${SPACEFX_DIR}/scripts/deploy_spacefx.sh"

}

main