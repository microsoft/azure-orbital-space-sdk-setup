#!/bin/bash
#
# Packages up and deploys env-config to the target container registry
#
# Example Usage:
#
#  "bash ./.vscode/build_tarball.sh"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
echo "Loading modules..."
source "$(dirname "$(realpath "$0")")/../modules/load_modules.sh" $@ --log_dir /var/log
echo "Modules loaded."

############################################################
# Script variables
############################################################
OUTPUT_DIR="${PWD}/output"
TEMP_DIR="${PWD}/tmp"
OUTPUT_FILENAME="msft-azure-orbital-sdk.tgz"
# DEST_REPO="env/config"
ARTIFACT_HASH=""
VERSION=""

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Packages up and deploys env-config to the target container registry"
   echo
   echo "Syntax: bash ./.vscode/build_env_config.sh"
   echo "options:"
   echo "--version                          [OPTIONAL] Override the version in the config file"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        --update-cr-url )
            shift
            CR_URL="$1"
        ;;
        --version )
            shift
            VERSION="$1"
        ;;
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done


if [[ -z "${VERSION}" ]]; then
    info_log "No version was supplied.  Checking for 'SERVICE_VERSION' environment variable...."
    if [[ -n "${SERVICE_VERSION}" ]]; then
        VERSION="${SERVICE_VERSION}"
        info_log "...found 'SERVICE_VERSION' environment variable.  Using SERVICE_VERSION '${SERVICE_VERSION}' as the version."
    else
        info_log "...no 'SERVICE_VERSION' environment variable found.  Using SPACEFX_VERSION '${SPACEFX_VERSION}' as the version."
        VERSION="${SPACEFX_VERSION}"
    fi
fi

############################################################
# Setup output directories
############################################################
function setup_directories(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Creating output directory '${OUTPUT_DIR}'..."

    [[ -d "${OUTPUT_DIR}" ]] && run_a_script "rm ${OUTPUT_DIR} -rf"
    run_a_script "mkdir -p ${OUTPUT_DIR}"
    info_log "...successfully created output directory '${OUTPUT_DIR}'."

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Copy the /var/spacedev back to temp directory so we can work on it
############################################################
function copy_to_local_tmp(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Creating temp directory '${TEMP_DIR}'..."
    [[ -d "${TEMP_DIR}" ]] && run_a_script "rm ${TEMP_DIR} -rf"
    run_a_script "bash ${PWD}/.vscode/copy_to_spacedev.sh --output_dir ${TEMP_DIR}"
    info_log "...successfully created temp directory '${TEMP_DIR}'."

    info_log "...running chmod +x and chmod 777 on all shell files in '${TEMP_DIR}/'..."
    while read -r shellFile; do
        run_a_script "chmod +x ${shellFile}" --disable_log
        run_a_script "chmod 777 ${shellFile}" --disable_log
    done < <(find "${TEMP_DIR}" -iname "*.sh")

    info_log "...done"

    if [[ -n "${CR_URL}" ]]; then
        info_log "Updating '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry URL to '${CR_URL}'..."
        run_a_script "yq eval '.config.containerRegistries[0].url = \"$CR_URL\"' -i \"${TEMP_DIR}/config/0_spacefx-base.yaml\""
        info_log "...successfully updated '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry URL to '${CR_URL}'."
    fi

    if [[ -n "${CR_PUSH_PERMISSION}" ]]; then
        info_log "Updating '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry push permission to '${CR_PUSH_PERMISSION}'..."
        run_a_script "yq eval '.config.containerRegistries[0].push_enabled = $CR_PUSH_PERMISSION' -i \"${TEMP_DIR}/config/0_spacefx-base.yaml\""
        info_log "...successfully updated '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry push permission to '${CR_PUSH_PERMISSION}'."
    fi

    if [[ -n "${CR_PULL_PERMISSION}" ]]; then
        info_log "Updating '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry pull permission to '${CR_PUSH_PERMISSION}'..."
        run_a_script "yq eval '.config.containerRegistries[0].pull_enabled = $CR_PUSH_PERMISSION' -i \"${TEMP_DIR}/config/0_spacefx-base.yaml\""
        info_log "...successfully updated '${TEMP_DIR}/config/0_spacefx-base.yaml' container registry pull permission to '${CR_PUSH_PERMISSION}'."
    fi


    info_log "Removing all config files except '0_spacefx-base.yaml'"

    while read -r configFile; do
        info_log "Removing '${configFile}'..."
        run_a_script "rm ${configFile}" --disable_log
        info_log "...successfully removed '${configFile}'"
    done < <(find "${TEMP_DIR}/config"  -maxdepth 1 -name "*.yaml" -type f ! -name "0_spacefx-base.yaml")

    info_log "Removing extra directories (if applicable)..."
    [[ -d "${TEMP_DIR}/logs" ]] && run_a_script "rm ${TEMP_DIR}/logs -rf"
    [[ -d "${TEMP_DIR}/temp" ]] && run_a_script "rm ${TEMP_DIR}/temp -rf"
    [[ -d "${TEMP_DIR}/certs" ]] && run_a_script "rm ${TEMP_DIR}/certs/*/*.crt" --ignore_error
    [[ -d "${TEMP_DIR}/certs" ]] && run_a_script "rm ${TEMP_DIR}/certs/*/*.pem" --ignore_error
    [[ -d "${TEMP_DIR}/certs" ]] && run_a_script "rm ${TEMP_DIR}/certs/*/*.key" --ignore_error
    [[ -d "${TEMP_DIR}/certs" ]] && run_a_script "rm ${TEMP_DIR}/certs/*/*.csr" --ignore_error
    [[ -d "${TEMP_DIR}/bin" ]] && run_a_script "rm ${TEMP_DIR}/bin -rf"
    [[ -d "${TEMP_DIR}/images" ]] && run_a_script "rm ${TEMP_DIR}/images -rf"
    [[ -d "${TEMP_DIR}/registry" ]] && run_a_script "rm ${TEMP_DIR}/registry -rf"
    [[ -d "${TEMP_DIR}/xfer" ]] && run_a_script "rm ${TEMP_DIR}/xfer -rf"
    [[ -d "${TEMP_DIR}/yamls" ]] && run_a_script "rm ${TEMP_DIR}/yamls/*.yaml -rf"
    [[ -d "${TEMP_DIR}/yamls/deploy" ]] && run_a_script "rm ${TEMP_DIR}/yamls/deploy/*.yaml -rf"
    info_log "...successfully removed any extra directories"

    info_log "Adding Service Version in spacefx.env to '${VERSION}'..."

    run_a_script "tee -a ${TEMP_DIR}/env/spacefx.env > /dev/null << SPACEFX_UPDATE_END

SERVICE_VERSION=${VERSION}

SPACEFX_UPDATE_END"

    info_log "...successfully updated Service Version in spacefx.env."


    info_log "...successfully copied to spacedev."

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Tar up the SPACEFX_DIR
############################################################
function create_tar_ball(){
    info_log "START: ${FUNCNAME[0]}"

    info_log "Building tarball '${OUTPUT_DIR}/${OUTPUT_FILENAME}' from '${TEMP_DIR}'..."

    run_a_script "tar -czf ${OUTPUT_DIR}/${OUTPUT_FILENAME} -C ${TEMP_DIR} ."

    run_a_script "sha256sum ${OUTPUT_DIR}/${OUTPUT_FILENAME}" ARTIFACT_HASH
    ARTIFACT_HASH="${ARTIFACT_HASH%% *}"

    info_log "...successfully built tarball '${OUTPUT_DIR}/${OUTPUT_FILENAME}'."

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    write_parameter_to_log TEMP_DIR
    write_parameter_to_log OUTPUT_DIR
    write_parameter_to_log OUTPUT_FILENAME
    write_parameter_to_log CR_URL
    write_parameter_to_log CR_PUSH_PERMISSION
    write_parameter_to_log CR_PULL_PERMISSION

    setup_directories
    copy_to_local_tmp
    create_tar_ball

    run_a_script "cp ${OUTPUT_DIR}/${OUTPUT_FILENAME} ${SPACEFX_DIR}/${OUTPUT_FILENAME}"

    run_a_script "bash ${SPACEFX_DIR}/build/push_build_artifact.sh --artifact ${SPACEFX_DIR}/${OUTPUT_FILENAME} --artifact-version ${VERSION} --architecture amd64 --annotation-config azure-orbital-space-sdk-setup.yaml"
    run_a_script "bash ${SPACEFX_DIR}/build/push_build_artifact.sh --artifact ${SPACEFX_DIR}/${OUTPUT_FILENAME} --artifact-version ${VERSION} --architecture arm64 --annotation-config azure-orbital-space-sdk-setup.yaml"

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main

