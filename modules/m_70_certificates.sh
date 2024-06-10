#!/bin/bash

############################################################
# Check if the root CA cert is available and if not, create it
############################################################
function check_and_create_certificate_authority() {
    # shellcheck disable=SC2154
    if [[ -f "${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem" ]]; then
        if [[ ! -f "${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt" ]]; then
            run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt"
        fi
        deploy_ca_cert_to_host
        return
    fi

    info_log "Generating '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem'..."

    create_directory "${SPACEFX_DIR}/certs/ca"

    cd "${SPACEFX_DIR}/certs/ca" || exit_with_error "Failed to cd to '${SPACEFX_DIR}/certs/ca'"

    run_a_script "cfssl gencert -initca ${SPACEFX_DIR}/certs/ca/ca.spacefx.json | cfssljson -bare ca.spacefx.local" --no_log_results

    cd - || exit_with_error "Failed to cd back"

    run_a_script "mv  ${SPACEFX_DIR}/certs/ca/ca.spacefx.local-key.pem  ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.key"

    info_log "...successfully generated '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem' and '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.key'"

    info_log "...removing old certificates that wasn't signed by the new ca..."

    while read -r certFile; do
        if [[ "${certFile}" != "${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem" ]]; then
            debug_log "Removing cert '${certFile}'..."
            run_a_script "rm ${certFile}"
            debug_log "...successfully removed '${certFile}'"
        fi
    done < <(find "${SPACEFX_DIR}/certs" -name "*.crt" -o -name "*.pem")

    run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt"
    deploy_ca_cert_to_host
}

############################################################
# Check if the certificate authority cert is in authorized certificate authorities for the host
############################################################
function deploy_ca_cert_to_host() {
    # shellcheck disable=SC2154
    if [[ -f "/usr/local/share/ca-certificates/ca.spacefx.local/ca.spacefx.local.crt" ]]; then
        if [[ ! -f "/etc/ssl/certs/ca.spacefx.local.pem" ]]; then
            run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem /etc/ssl/certs/ca.spacefx.local.pem"
        fi
        is_cmd_available "update-ca-certificates" has_cmd
        if [[ "${has_cmd}" == true ]]; then
            run_a_script "update-ca-certificates"
        fi
        return
    fi

    info_log "Deploying '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem' to host..."
    create_directory "/usr/local/share/ca-certificates/ca.spacefx.local"

    run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt /usr/local/share/ca-certificates/ca.spacefx.local/ca.spacefx.local.crt"
    run_a_script "ln -sf ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem /etc/ssl/certs/ca.spacefx.local.pem"

    info_log "...adding cert..."

    # Doing it this way lets us add to the host's chain incase we don't have update-ca-certificates
    run_a_script "cat ${SPACEFX_DIR}/certs/ca/ca.spacefx.local.crt" space_fx_ca_cert
    run_a_script "cat /etc/ssl/certs/ca-certificates.crt" current_ca_certs

    run_a_script "tee /etc/ssl/certs/ca-certificates.crt > /dev/null << SPACEFX_UPDATE_END
${current_ca_certs}
${space_fx_ca_cert}
SPACEFX_UPDATE_END"

    is_cmd_available "update-ca-certificates" has_cmd
    if [[ "${has_cmd}" == true ]]; then
        run_a_script "update-ca-certificates"
    fi

    info_log "...successfully deployed '${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem' to host..."

}

############################################################
# Remove all certs.
############################################################
function remove_all_certs() {
    create_directory "${SPACEFX_DIR}/certs"

    debug_log "Removing all certifcate artifactes from '${SPACEFX_DIR}/certs'..."

    while read -r certFile; do
        info_log "...removing '${certFile}'..."
        run_a_script "rm ${certFile}"
        info_log "...successfully removed '${certFile}'..."
    done < <(find "${SPACEFX_DIR}/certs" -name "*.crt" -o -name "*.pem" -o -name "*.key" -o -name "*.csr")

    is_cmd_available "update-ca-certificates" has_cmd

    if [[ "${has_cmd}" == true ]]; then
        run_a_script "update-ca-certificates"
    fi

    debug_log "...successfully removed all certificate artifacts from '${SPACEFX_DIR}/certs'"
}

############################################################
# Create a certificate
############################################################
function generate_certificate() {
    check_and_create_certificate_authority

    local cert_profile=""
    local cert_config=""
    local output_dir=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --profile)
                shift
                cert_profile=$1
                ;;
            --config)
                shift
                cert_config=$1
                ;;
            --output)
                shift
                output_dir=$1
                # Removing the trailing slash if there is one
                output_dir=${output_dir%/}
                ;;
        esac
        shift
    done

    if [[ -z "${cert_profile}" ]]; then
        exit_with_error "Missing --profile parameter.  Please use function like generate_certificate --profile 'some-profile.json' --config 'some-config.json' --output '${SPACEFX_DIR}/certs/etc'"
    fi

    if [[ -z "${cert_config}" ]]; then
        exit_with_error "Missing --config parameter.  Please use function like generate_certificate --profile 'some-profile.json' --config 'some-config.json' --output '${SPACEFX_DIR}/certs/etc'"
    fi

    if [[ -z "${output_dir}" ]]; then
        exit_with_error "Missing --output parameter.  Please use function like generate_certificate --profile 'some-profile.json' --config 'some-config.json' --output '${SPACEFX_DIR}/certs/etc'"
    fi

    if [[ ! -f "${cert_profile}" ]]; then
        exit_with_error "--profile value '${cert_profile}' not found.  Please check that file '${cert_profile}' exists"
    fi

    if [[ ! -f "${cert_config}" ]]; then
        exit_with_error "--profile value '${cert_config}' not found.  Please check that file '${cert_config}' exists"
    fi

    run_a_script "jq -r '.CN' ${cert_profile}" cert_name --ignore_error

    if [[ -z "${cert_name}" ]]; then
        exit_with_error "Unable to calculate CN from '${cert_profile}'.  No CN found"
    fi

    if [[ -f "${output_dir}/${cert_name}.pem" ]]; then
        # Certificate already exists.  Nothing to do.
        if [[ ! -f "${output_dir}/${cert_name}.crt" ]]; then
            run_a_script "cp ${output_dir}/${cert_name}.pem ${output_dir}/${cert_name}.crt"
        fi
        return
    fi

    create_directory ${output_dir}

    if [[ -f "${output_dir}/${cert_name}.crt" ]]; then
        debug_log "Removing out-of-date '${output_dir}/${cert_name}.crt'"
        run_a_script "rm ${output_dir}/${cert_name}.crt"
        debug_log "...successfully removed out-of-date '${output_dir}/${cert_name}.crt'"
    fi

    info_log "Generating '${output_dir}/${cert_name}.pem'..."

    cd "${output_dir}" || exit_with_error "Failed to cd to '${output_dir}'"

    run_a_script "cfssl gencert -ca=${SPACEFX_DIR}/certs/ca/ca.spacefx.local.pem -ca-key=${SPACEFX_DIR}/certs/ca/ca.spacefx.local.key -config=${cert_config} -profile=server ${cert_profile} | cfssljson -bare ${cert_name}" --no_log_results

    cd - || exit_with_error "Failed to cd back"

    run_a_script "cp ${output_dir}/${cert_name}.pem ${output_dir}/${cert_name}.crt"
    run_a_script "mv ${output_dir}/${cert_name}-key.pem ${output_dir}/${cert_name}.key"

    info_log "...successfully generated '${output_dir}/${cert_name}.pem' and '${output_dir}/${cert_name}.key'..."
}
