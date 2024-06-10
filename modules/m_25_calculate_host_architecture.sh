#!/bin/bash

############################################################
# Calculates the host architecture and the current architecture
############################################################
function _calculate_host_architecture() {
    run_a_script "uname -m" HOST_ARCHITECTURE --disable_log

    if [[ "${HOST_ARCHITECTURE}" == "x86_64" ]]; then
        HOST_ARCHITECTURE="amd64"
    elif [[ "${HOST_ARCHITECTURE}" == "aarch64" ]]; then
        HOST_ARCHITECTURE="arm64"
    fi

    # The ARCHITECTURE variable is not set, so we need to calculate it
    if [[ -z "${ARCHITECTURE}" ]]; then
        run_a_script "uname -m" ARCHITECTURE --disable_log

        if [[ "${ARCHITECTURE}" == "x86_64" ]]; then
            ARCHITECTURE="amd64"
        elif [[ "${ARCHITECTURE}" == "aarch64" ]]; then
            ARCHITECTURE="arm64"
        fi
    fi

    write_parameter_to_log ARCHITECTURE
    write_parameter_to_log HOST_ARCHITECTURE
}