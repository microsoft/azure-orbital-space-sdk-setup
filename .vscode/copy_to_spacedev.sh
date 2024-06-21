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
REPO_ROOT_DIR=$(git rev-parse --show-toplevel)
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
function copy_directory_to_dest(){
  local directory=""

  while [[ "$#" -gt 0 ]]; do
      case $1 in
          --directory)
              shift
              directory=$1
              ;;
          *)
              echo "Unknown parameter '$1'"
              exit 1
              ;;
      esac
      shift
  done

  echo "...copying '${REPO_ROOT_DIR}/${directory}' to '${OUTPUT_DIR}/${directory}'..."

  sudo mkdir -p "${OUTPUT_DIR}/${directory}"
  sudo rsync -a --update --no-links \
        --exclude='/*.log' \
        --exclude='/*.pem' \
        --exclude='/*.csr' \
        --exclude='/*.key' \
        --exclude='/*.crt' \
        "${REPO_ROOT_DIR}/${directory}/" "${OUTPUT_DIR}/${directory}/"

  if [[ $? -gt 0 ]]; then
    echo "...error copying '${REPO_ROOT_DIR}/${directory}' to '${OUTPUT_DIR}/${directory}'"
    exit 1
  fi

  echo "...successfully copied '${REPO_ROOT_DIR}/${directory}' to '${OUTPUT_DIR}/${directory}'..."

}

function main() {
  [[ $REPO_ROOT_DIR == *".vscode"* ]] && REPO_ROOT_DIR=$(dirname "$REPO_ROOT_DIR")

  # shellcheck disable=SC1091
  # shellcheck disable=SC2068
  source "${REPO_ROOT_DIR}/env/spacefx.env"

  [[ -z "${OUTPUT_DIR}" ]] && OUTPUT_DIR="${SPACEFX_DIR}"

  [[ -d "${OUTPUT_DIR}" ]] && sudo rm "${OUTPUT_DIR}" -rf

  [[ ! -d "${OUTPUT_DIR}" ]] && sudo mkdir -p "${OUTPUT_DIR}"

  echo "Copying Azure Orbital Space SDK to '${OUTPUT_DIR}'..."

  copy_directory_to_dest --directory "build"
  copy_directory_to_dest --directory "certs"
  copy_directory_to_dest --directory "chart"
  copy_directory_to_dest --directory "config"
  copy_directory_to_dest --directory "env"
  copy_directory_to_dest --directory "modules"
  copy_directory_to_dest --directory "protos"
  copy_directory_to_dest --directory "scripts"

  while read -r shellFile; do
    chmod +x ${shellFile}
    chmod 777 ${shellFile}
  done < <(find "${OUTPUT_DIR}" -iname "*.sh")

  echo "...successfully copied Azure Orbital Space SDK to '${OUTPUT_DIR}'."

  sudo chown -R "${USER:-$(id -un)}" "${OUTPUT_DIR}"

}


main



