#!/bin/bash
#
# Copies the repo files to the spacefx_dir
#
# Example Usage:
#
#  "bash ./.vscode/copy-to-spacedev.sh [--disable_purge]

############################################################
# Script variables
############################################################
REPO_ROOT_DIR=$(dirname "$0")
OUTPUT_DIR=""
############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --output-dir)
            shift
            OUTPUT_DIR=$1
            ;;
    esac
    shift
done

############################################################
# Clean up the destination directory by removing the sensitive parts so they can be restaged
############################################################
function clean_up_dest_directory(){
  [[ -d "${OUTPUT_DIR}/logs" ]] &&  sudo rm -rf "${OUTPUT_DIR}/logs"
  [[ -d "${OUTPUT_DIR}/tmp" ]] &&  sudo rm -rf "${OUTPUT_DIR}/tmp"
  [[ -d "${OUTPUT_DIR}/output" ]] &&  sudo rm -rf "${OUTPUT_DIR}/output"
  [[ -d "${OUTPUT_DIR}/xfer" ]] &&  sudo rm -rf "${OUTPUT_DIR}/xfer"
  [[ -d "${OUTPUT_DIR}/plugins" ]] &&  sudo rm -rf "${OUTPUT_DIR}/plugins"
  [[ -f "${OUTPUT_DIR}/chart/Charts.lock" ]] &&  sudo rm -f "${OUTPUT_DIR}/chart/Charts.lock"
  [[ -f "${OUTPUT_DIR}/certs/*/*.crt" ]] &&  sudo rm -f "${OUTPUT_DIR}/certs/*/*.crt"


  while read -r shellFile; do
    chmod +x ${shellFile}
    chmod 777 ${shellFile}
  done < <(find "${OUTPUT_DIR}" -iname "*.sh")
}

function main() {
  [[ $REPO_ROOT_DIR == *".vscode"* ]] && REPO_ROOT_DIR=$(dirname "$REPO_ROOT_DIR")

  # shellcheck disable=SC1091
  # shellcheck disable=SC2068
  source "${REPO_ROOT_DIR}/env/spacefx.env"

  [[ -z "${OUTPUT_DIR}" ]] && OUTPUT_DIR="${SPACEFX_DIR}"

  [[ -d "${OUTPUT_DIR}" ]] && sudo rm "${OUTPUT_DIR}" -rf

  [[ ! -d "${OUTPUT_DIR}" ]] && sudo mkdir -p "${OUTPUT_DIR}"

  echo "...outputting to '${OUTPUT_DIR}'..."

  eval "sudo rsync -a --update --no-links \
        --exclude='/.devcontainer' \
        --exclude='/.pipelines' \
        --exclude='/.vscode' \
        --exclude='/.git' \
        --exclude='/.git*' \
        --exclude='/docs' \
        --exclude='/tmp' \
        --exclude='/logs' \
        --exclude='/output' \
        --exclude='/owners.txt' \
        --exclude='/*.md' \
        --exclude='/LICENSE' \
        --exclude='/*.log' \
        --exclude='/*.gitignore' \
        --exclude='/*.gitattributes' \
        --exclude='/spacedev_cache' \
        --exclude='/.shellcheckrc' \
        --exclude='/tests' \
        '${REPO_ROOT_DIR}/' '${OUTPUT_DIR}/'"

  clean_up_dest_directory

  echo "...successfully outputted to '${OUTPUT_DIR}'."

  sudo chown -R "${USER:-$(id -un)}" "${OUTPUT_DIR}"

}


main

