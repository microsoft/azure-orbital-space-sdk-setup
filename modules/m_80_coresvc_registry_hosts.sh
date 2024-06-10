#!/bin/bash

############################################################
# Add the hosts entry for core registry
############################################################
function _check_for_coresvc_registry_hosts_entry() {
    run_a_script "cat /etc/hosts" current_etc_hosts --disable_log
    if [[ $current_etc_hosts == *"registry.spacefx.local"* ]]; then
        return
    fi

    trace_log "Adding 'registry.spacefx.local' HOSTS entry to '127.0.0.1'...."

    run_a_script "tee -a /etc/hosts > /dev/null << SPACEFX_END
${current_etc_hosts}
127.0.0.1 registry.spacefx.local
SPACEFX_END" --disable_log

    trace_log "Successfully added 127.0.0.1 to hosts"

}