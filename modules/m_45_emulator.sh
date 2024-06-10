#!/bin/bash

############################################################
# Waits for a deployment to finish in kubernetes
############################################################
function provision_emulator() {

    if [[ "${HOST_ARCHITECTURE}" == "${ARCHITECTURE}" ]]; then
        trace_log "Host architecture '${HOST_ARCHITECTURE}' matches requested architecture '${ARCHITECTURE}'.  Nothing to do"
        return
    fi

    is_cmd_available "docker" has_cmd
    # shellcheck disable=SC2154
    if [ "${has_cmd}" == false ]; then
        exit_with_error "...docker not found.  Can't provision emulator.  See https://docs.docker.com/engine/install/ubuntu/ for installation instructions"
    fi


    trace_log "Host Architecture differs from target architecture ('${HOST_ARCHITECTURE}' != '${ARCHITECTURE}').  Provisioning emulator..."
    run_a_script "docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
    trace_log "...successfully provisioned emulator"

    export DOCKER_DEFAULT_PLATFORM="linux/${ARCHITECTURE}"
}