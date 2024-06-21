#!/bin/bash

############################################################
# Update helm chart values file for /var/spacedev
############################################################
function _update_helm_values_for_spacefx_base() {
    trace_log "Updating .global.spacefxDirectories.base to '${SPACEFX_DIR}' in '${SPACEFX_DIR}/chart/values.yaml'..."

    run_a_script "yq eval '.global.spacefxDirectories.base = \"${SPACEFX_DIR}\"' ${SPACEFX_DIR}/chart/values.yaml" values_yaml --disable_log
    run_a_script "tee ${SPACEFX_DIR}/chart/values.yaml > /dev/null << SPACEFX_END
${values_yaml}
SPACEFX_END" --disable_log

    run_a_script "yq eval '.global.architecture = \"${ARCHITECTURE}\"' ${SPACEFX_DIR}/chart/values.yaml" values_yaml --disable_log

    run_a_script "tee ${SPACEFX_DIR}/chart/values.yaml > /dev/null << SPACEFX_END
${values_yaml}
SPACEFX_END" --disable_log

    trace_log "...successfully updated .global.spacefxDirectories.base to '${SPACEFX_DIR}' in '${SPACEFX_DIR}/chart/values.yaml'."

}

############################################################
# Generate the spacefx-config.json file used by the rest of the scripts
############################################################
function _generate_spacefx_config_json() {
    local yq_query=""
    trace_log "Generating '${SPACEFX_DIR}/tmp/config/spacefx-config.json'..."

    create_directory "${SPACEFX_DIR}/tmp/config"

    if [[ "${SPACEFX_CHANNEL}" != "stable" ]]; then
        debug_log "Channel '${SPACEFX_CHANNEL}' detected.  Copying channel config '${SPACEFX_DIR}/config/channels/${SPACEFX_CHANNEL}.yaml' to '${SPACEFX_DIR}/config/${SPACEFX_CHANNEL}.yaml'."
        [[ ! -f "${SPACEFX_DIR}/config/channels/${SPACEFX_CHANNEL}.yaml" ]] && exit_with_error "Channel config '${SPACEFX_DIR}/config/channels/${SPACEFX_CHANNEL}.yaml' does not exist. Please update the channel in spacefx.env and try again."
        run_a_script "cp ${SPACEFX_DIR}/config/channels/${SPACEFX_CHANNEL}.yaml ${SPACEFX_DIR}/config/${SPACEFX_CHANNEL}.yaml" --disable_log
    fi

    # Build the JSON output from the configuration in yq
    # This'll take all the yamls in config and generate the
    # json file
    run_a_script "yq ea '. as \$item ireduce ({}; . * \$item )' ${SPACEFX_DIR}/config/*.yaml --output-format=json" spacefx_json_config --disable_log


    run_a_script "tee ${SPACEFX_DIR}/tmp/config/spacefx-config.json > /dev/null << SPACEFX_END
${spacefx_json_config}
SPACEFX_END" --disable_log

    trace_log "...successfully generated '${SPACEFX_DIR}/tmp/config/spacefx-config.json'."

}