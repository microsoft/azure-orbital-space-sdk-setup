#!/bin/bash

############################################################
# Add an entry in etc/hosts to point to the coresvc registry
############################################################
function _check_for_coresvc_registry_hosts_entry(){

    info_log "Adding hosts entry for coresvc registry"

    [[ ! -f "/etc/hosts" ]] && exit_with_error "Unable to find /etc/hosts file"

    run_a_script "cat /etc/hosts" _hosts_file --disable_log


    debug_log "...retrieving coresvc-registry external url..."

    run_a_script "yq '.global.containerRegistry' ${SPACEFX_DIR}/chart/values.yaml" _registry_url
    _registry_url="${_registry_url%%:*}"

    debug_log "...coresvc-registry external url: '${_registry_url}'"

    if [[ "$_hosts_file" == *"$_registry_url"* ]]; then
        debug_log "...hosts entry already exists for '${_registry_url}'.  Nothing to do"
        return
    fi

    debug_log "...hosts entry not found for '${_registry_url}'.  Adding..."

    if [[ -n "${REMOTE_CONTAINERS}" ]]; then
        debug_log "DevContainer detected.  Calculating external host ip"

        # Calculate the external ip of the host by checking the routes used to get to the internet
        run_a_script_on_host "ip route get 8.8.8.8" host_ip
        host_ip=${host_ip#*src }
        host_ip=${host_ip%% *}
        debug_log "...external ip: '${host_ip}'"
    else
        debug_log "DevContainer not detected.  Using 127.0.0.1 as ip"
        host_ip="127.0.0.1"
    fi

    run_a_script "tee -a /etc/hosts > /dev/null << SPACEFX_UPDATE_END
${host_ip}       ${_registry_url}
SPACEFX_UPDATE_END" --disable_log

debug_log "...successfully added hosts entry for '${_registry_url}' to '${host_ip}'..."

}

############################################################
# Add an entry in etc/hosts to point to the coresvc registry in devcontainers
############################################################
function _check_for_coresvc_registry_hosts_entry_devcontainer(){

    # KUBECONFIG is not set for some reason.  End cleanly
    [[ -z "${KUBECONFIG}" ]] && return

    # No /etc/hosts file.  End cleanly
    [[ ! -f "/etc/hosts" ]] && return

    run_a_script "cat /etc/hosts" _hosts_file --disable_log

    # The hosts entry is already added.  Nothing to do.  End cleanly
    [[ "$_hosts_file" == *"coresvc-registry.coresvc.svc.cluster.local"* ]] && return

    # Kubectl is not available.  End cleanly
    is_cmd_available "kubectl" has_cmd
    [[ "${has_cmd}" == false ]] && return

    # Check if coresvc-registry has an service ip
    run_a_script "kubectl get service/coresvc-registry -n coresvc --output json | jq -r '.spec.clusterIP'" coresvc_registry_ip --ignore_error

    # No service ip.  End cleanly
    [[ -z "${coresvc_registry_ip}" ]] && return

    info_log "Adding /etc/hosts for 'coresvc-registry.coresvc.svc.cluster.local' to '${coresvc_registry_ip}'"

    write_to_file --file "/etc/hosts" --file_contents "${coresvc_registry_ip}       coresvc-registry.coresvc.svc.cluster.local" --append

    debug_log "...successfully added hosts entry for 'coresvc-registry.coresvc.svc.cluster.local' to '${coresvc_registry_ip}'."

}