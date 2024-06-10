#!/bin/bash

############################################################
# Update regctl configuration for core-registry
############################################################
function _update_regctl_config() {

    # Gotta run it twice because regctl keeps sudo config in a difference spot
    run_a_script "regctl registry set localhost:5000 --tls enabled --req-concurrent 15 --req-per-sec 15 --skip-check" --disable_log
    run_a_script "regctl registry set localhost:5000 --tls enabled --req-concurrent 15 --req-per-sec 15 --skip-check" --no_sudo --disable_log

    # Gotta run it twice because regctl keeps sudo config in a difference spot
    run_a_script "regctl registry set registry.spacefx.local --tls enabled --req-concurrent 15 --req-per-sec 15 --hostname localhost:5000 --skip-check" --disable_log
    run_a_script "regctl registry set registry.spacefx.local --tls enabled --req-concurrent 15 --req-per-sec 15 --hostname localhost:5000 --skip-check"  --no_sudo --disable_log
}