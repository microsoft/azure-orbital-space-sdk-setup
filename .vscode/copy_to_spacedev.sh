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
PURGE_SPACEFX_DIR=true
CLEAN_DEST_DIR=true
REPO_ROOT_DIR=$(dirname "$0")
OUTPUT_DIR=""
############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --disable_purge)
            PURGE_SPACEFX_DIR=false
            CLEAN_DEST_DIR=false
            ;;
        --disable_dest_clean)
            CLEAN_DEST_DIR=false
            ;;
        --output_dir)
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
}

function main() {
  [[ $REPO_ROOT_DIR == *".vscode"* ]] && REPO_ROOT_DIR=$(dirname "$REPO_ROOT_DIR")

  # shellcheck disable=SC1091
  # shellcheck disable=SC2068
  source "${REPO_ROOT_DIR}/env/spacefx.env"

  [[ -z "${OUTPUT_DIR}" ]] && OUTPUT_DIR="${SPACEFX_DIR}"

  [[ ! -d "${OUTPUT_DIR}" ]] && sudo mkdir -p "${OUTPUT_DIR}"

  echo "...outputting to '${OUTPUT_DIR}'..."

  if [[ "${PURGE_SPACEFX_DIR}" == true ]]; then
    sudo rm "${OUTPUT_DIR}/*" -rf
  fi


  eval "sudo rsync -a --update --no-links \
        --exclude='/tmp' \
        --exclude='/.pipelines' \
        --exclude='/.vscode' \
        --exclude='/.git' \
        --exclude='/.git*' \
        --exclude='/docs' \
        --exclude='/tmp' \
        --exclude='/logs' \
        --exclude='/output' \
        --exclude='/owners.txt' \
        '${REPO_ROOT_DIR}/' '${OUTPUT_DIR}/'"

  [[ "${CLEAN_DEST_DIR}" == true ]] && clean_up_dest_directory


  echo "...successfully outputted to '${OUTPUT_DIR}'."


  sudo chown -R "${USER:-$(id -un)}" "${OUTPUT_DIR}"

}


main
