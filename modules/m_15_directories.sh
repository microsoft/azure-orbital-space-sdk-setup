#!/bin/bash

############################################################
# Creates a new directory and grants access to it
############################################################
function create_directory() {
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing directory path to create.  Please use function like create_directory path_to_directory"
    fi

    local dir_to_create=$1

    [[ -d "${dir_to_create}" ]] && return

    run_a_script "mkdir -p ${dir_to_create}" --disable_log
    run_a_script "chmod -R 777 ${dir_to_create}" --disable_log
    run_a_script "chown -R ${USER:-$(id -un)} ${dir_to_create}" --disable_log
}


function _setup_initial_directories() {
    create_directory "${SPACEFX_DIR}/bin"
    create_directory "${SPACEFX_DIR}/logs"
    create_directory "${SPACEFX_DIR}/plugins"
    create_directory "${SPACEFX_DIR}/tmp"
    create_directory "${SPACEFX_DIR}/tmp/yamls"
    create_directory "${SPACEFX_DIR}/xfer"
}