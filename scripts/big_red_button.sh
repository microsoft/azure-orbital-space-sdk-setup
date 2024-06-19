#!/bin/bash
#
#  Big Red Button completely removes all containers, uninstalls k3s, and removes all files within spacedev.
#
# arguments:
#
#
# Example Usage:
#
#  "bash ./scripts/big_red_button.sh"
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../modules/load_modules.sh" $@ --log_dir /var/log --no_app_installs

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Completely removes all containers, uninstalls k3s, and removes all files within spacedev."
   echo
   echo "Syntax: bash ./scripts/big_red_button.sh"
   echo "options:"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options. Add options as needed.        #
############################################################
# Get the options

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done

function show_header() {
    info_log "  ____  _         _____          _   ____        _   _              "
    info_log " |  _ \(_)       |  __ \        | | |  _ \      | | | |             "
    info_log " | |_) |_  __ _  | |__) |___  __| | | |_) |_   _| |_| |_ ___  _ __  "
    info_log " |  _ <| |/ _  | |  _  // _ \/ _  | |  _ <| | | | __| __/ _ \|  _ \ "
    info_log " | |_) | | (_| | | | \ \  __/ (_| | | |_) | |_| | |_| || (_) | | | |"
    info_log " |____/|_|\__, | |_|  \_\___|\__,_| |____/ \__,_|\__|\__\___/|_| |_|"
    info_log "           __/ |                                                   "
    info_log "          |___/                                                    "
}

############################################################
# Stops the k3s service if it's running
############################################################
function check_and_disable_k3s() {
    if [[ -f "/etc/systemd/system/k3s.service" ]]; then
        info_log "Disabling k3s service"
        run_a_script "systemctl disable k3s"
        run_a_script "systemctl stop k3s"
    fi
}

############################################################
# Stops and removes all docker containers
############################################################
function stop_all_docker_containers() {
    info_log "START: ${FUNCNAME[0]}"

    is_cmd_available "docker" has_cmd

    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == false ]]; then
        info_log "...docker not found.  Nothing do to"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Pausing all docker containers..."
    run_a_script "docker ps -q" all_docker_containers --disable_log

    for container_id in $all_docker_containers; do
        info_log "...pausing container id ${container_id}..."
        run_a_script "docker pause ${container_id}" --ignore_error --disable_log
    done

    info_log "...stopping container processes..."

    docker_pids=$(ps -e | grep 'containerd-shim' | awk '{print $1}')

    # Kill the Docker container processes
    for pid in $docker_pids; do
        run_a_script "kill -9 $pid" --disable_log
    done

    info_log "...removing containers...."
    run_a_script "docker ps -a -q" all_docker_containers --disable_log

    for container_id in $all_docker_containers; do
        info_log "...removing container id ${container_id}..."
        run_a_script "docker rm ${container_id} -f" results --ignore_error --disable_log
    done

    info_log "...all docker containers removed."

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Uninstall k3s
############################################################
function remove_k3s() {
    info_log "START: ${FUNCNAME[0]}"

    is_cmd_available "k3s" has_cmd
    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == false ]]; then
        info_log "...k3s not found.  Nothing do to"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "...k3s found.  Uninstalling..."
    [[ -f "/usr/local/bin/k3s-uninstall.sh" ]] && run_a_script "/usr/local/bin/k3s-uninstall.sh"

    info_log "...k3s successfully uninstalled"


    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Prune Docker
############################################################
function prune_docker() {
    info_log "START: ${FUNCNAME[0]}"

    is_cmd_available "docker" has_cmd

    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == false ]]; then
        info_log "...docker not found.  Nothing do to"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Pruning docker..."
    run_a_script "docker system prune --all --volumes --force"
    info_log "...docker pruned."

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    show_header

    check_and_disable_k3s

    stop_all_docker_containers
    remove_k3s
    prune_docker

    info_log "Removing '${SPACEFX_DIR:?}'..."
    run_a_script "rm -rf ${SPACEFX_DIR:?}"
    info_log "...successfully removed '${SPACEFX_DIR:?}'"

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main