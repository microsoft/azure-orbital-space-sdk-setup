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
# Uninstall k3s
############################################################
function remove_k3s() {
    info_log "START: ${FUNCNAME[0]}"

    info_log "Removing k3s..."

    is_cmd_available "k3s" has_cmd
    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == false ]]; then
        info_log "...k3s not found.  Nothing do to"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    run_a_script "systemctl is-active k3s" K3S_STATUS --ignore_error
    if [[ "${K3S_STATUS}" == "active" ]]; then
        info_log "...stopping k3s..."
        run_a_script "systemctl stop k3s"
    fi

    # If we're using docker, then pause all the docker containers so k3s uninstalls faster
    is_cmd_available "docker" has_cmd
    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == true ]]; then
        info_log "...pausing containers..."

        run_a_script "docker ps -q" all_docker_containers --disable_log

        for container_id in $all_docker_containers; do
            info_log "...pausing container id ${container_id}..."
            run_a_script "docker pause ${container_id}" --ignore_error --disable_log
        done
    fi

    info_log "...uninstalling k3s..."
    [[ -f "/usr/local/bin/k3s-uninstall.sh" ]] && run_a_script "/usr/local/bin/k3s-uninstall.sh"

    info_log "...k3s successfully removed"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Remove everything in docker
############################################################
function purge_docker() {
    info_log "START: ${FUNCNAME[0]}"

    is_cmd_available "docker" has_cmd

    # shellcheck disable=SC2154
    if [[ "${has_cmd}" == false ]]; then
        info_log "...docker not found.  Nothing do to"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "Stoping all docker containers..."

    docker_pids=$(ps -e | grep 'containerd-shim' | awk '{print $1}')

    # Kill the Docker container processes
    for pid in $docker_pids; do
        run_a_script "kill -9 $pid" --disable_log
    done

    info_log "Removing all docker containers...."
    run_a_script "docker ps -a -q" all_docker_containers --disable_log

    for container_id in $all_docker_containers; do
        info_log "...removing container id ${container_id}..."
        run_a_script "docker rm ${container_id} -f" results --ignore_error --disable_log
    done

    info_log "Checking if containers need another pass..."
    run_a_script "docker ps -a -q" second_pass_docker_containers --disable_log

    for container_id in $second_pass_docker_containers; do
        info_log "...removing container id ${container_id}..."
        run_a_script "docker rm ${container_id} -f" results --ignore_error --disable_log
    done

    info_log "...all docker containers removed."

    info_log "Purging docker..."
    run_a_script "docker system prune --all --volumes --force"
    info_log "...docker purged."

    info_log "END: ${FUNCNAME[0]}"
}

function main() {
    show_header

    purge_docker
    remove_k3s


    run_a_script "rm -rf ${SPACEFX_DIR:?}"

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main