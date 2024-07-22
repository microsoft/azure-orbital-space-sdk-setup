#!/bin/bash
#
# Locally builds the service container images from _base to full images for the Azure Orbital Space SDK.
#
# Example Usage:
#
#  "bash ./scripts/deploy/build_service_images.sh"

# Load the modules and pass all the same parameters that we're passing here
# shellcheck disable=SC1091
# shellcheck disable=SC2068
source "$(dirname "$(realpath "$0")")/../../modules/load_modules.sh" $@ --no_internet

############################################################
# Script variables
############################################################
BUILDSVC_NAMESPACE=""

############################################################
# Help                                                     #
############################################################
function show_help() {
   # Display Help
   echo "Deploys the helm chart dependencies used by the Azure Orbital Space SDK for use in an airgapped, non-internet connected environment."
   echo
   echo "Syntax: bash ./scripts/deploy/build_service_images.sh"
   echo "options:"
   echo "--help | -h                        [OPTIONAL] Help script (this screen)"
   echo
   exit 1
}


############################################################
# Process the input options.
############################################################
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -h|--help) show_help ;;
        *) echo "Unknown parameter '$1'"; show_help ;;
    esac
    shift
done


############################################################
# Loop through the services and trigger a build for each one
############################################################
function build_service_group(){
    info_log "START: ${FUNCNAME[0]}"

    local service_group=""
    local build_triggered=false

    local environment_filter="prod"
    [[ "${DEV_ENVIRONMENT}" == true ]] && environment_filter="dev"

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --service_group)
                shift
                service_group=$1
                ;;
        esac
        shift
    done

    info_log "Scanning service group '${service_group}' for building..."

    run_a_script "yq '.' ${SPACEFX_DIR}/chart/values.yaml --output-format=json | jq '.services.${service_group} | to_entries[] | select(.value.${environment_filter}.enabled == true and .value.${environment_filter}.hasBase == true) | {appName: .value.appName, serviceNameSpace: .value.serviceNamespace, repository: .value.repository, contextDir: .value.buildService.contextDir, dockerFile: .value.buildService.dockerFile, workingDirectory: .value.workingDir} | @base64' -r" spacefx_services

    for spacefx_service in $spacefx_services; do
        parse_json_line --json "${spacefx_service}" --property ".appName" --result spacefx_service_appName
        parse_json_line --json "${spacefx_service}" --property ".repository" --result spacefx_service_repository
        parse_json_line --json "${spacefx_service}" --property ".dockerFile" --result spacefx_service_dockerFile
        parse_json_line --json "${spacefx_service}" --property ".contextDir" --result spacefx_service_contextDir
        parse_json_line --json "${spacefx_service}" --property ".workingDirectory" --result spacefx_service_workingDirectory

        info_log "Checking for previous build for service '${spacefx_service_appName}'..."
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get job -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/serviceName\"=\"${spacefx_service_appName}\" -o json | jq '.items | length'" previous_runs --ignore_error
        previous_runs=$((previous_runs)) # Interpret as integer

        if [[ -n "${previous_runs}" ]] && [[ "${previous_runs}" -gt 0 ]]; then
            info_log "Previous build found for service '${spacefx_service_appName}'.  Skipping..."
            continue
        fi

        info_log "Building service '${spacefx_service_appName}'..."

        debug_log "Generating build yaml..."
        run_a_script "helm --kubeconfig ${KUBECONFIG} template ${SPACEFX_DIR}/chart --set services.core.buildservice.enabled=true \
                --set services.core.buildservice.targetService.appName=${spacefx_service_appName} \
                --set services.core.buildservice.targetService.repository=${spacefx_service_repository} \
                --set services.core.buildservice.targetService.dockerFile=${spacefx_service_dockerFile} \
                --set services.core.buildservice.targetService.contextDir=${spacefx_service_contextDir} \
                --set services.core.buildservice.targetService.workingDirectory=${spacefx_service_workingDirectory} \
                --set services.core.buildservice.targetService.tag=${SPACEFX_VERSION}" build_yaml

        debug_log "Triggering build..."

        run_a_script "kubectl --kubeconfig ${KUBECONFIG} apply -f - <<SPACEFX_UPDATE_END
${build_yaml}
SPACEFX_UPDATE_END"

        build_triggered=true
    done

    if [[ "${build_triggered}" == false ]]; then
        info_log "No builds were triggered.  Nothing to do."
        info_log "FINISHED: ${FUNCNAME[0]}"
        return
    fi

    monitor_build_service --service_group "${service_group}"

    info_log "FINISHED: ${FUNCNAME[0]}"
}

############################################################
# Wait for build service to finish processing and get the logs
############################################################
function monitor_build_service(){
    info_log "START: ${FUNCNAME[0]}"

    local service_group=""
    local environment_filter="prod"
    [[ "${DEV_ENVIRONMENT}" == true ]] && environment_filter="dev"

    start_time=$(date +%s)

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --service_group)
                shift
                service_group=$1
                ;;
        esac
        shift
    done

    info_log "All services in '${service_group}' queued for build.  Waiting for builds to finish (max '${MAX_WAIT_SECS}' secs)..."

    run_a_script "kubectl --kubeconfig ${KUBECONFIG} get job -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '.items | length'" current_jobs
    current_jobs=$((current_jobs)) # Interpret as integer
    while [[ "${current_jobs}" -eq 0 ]]; do
        info_log "No build jobs seens yet.  Will recheck in 3 seconds..."
        sleep 3
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get job -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '.items | length'" current_jobs
        current_jobs=$((current_jobs)) # Interpret as integer

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge 30 ]]; then
            exit_with_error "Timed out waiting for build service to start.  Check if an error has happened, or restart deploy_spacefx.sh"
        fi

    done

    info_log "Build jobs have started.  Waiting for them to finish"

    # Set the running jobs to be greater than 0 to start the loop
    running_jobs=1

    while [[ "${running_jobs}" -gt 0 ]]; do
        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get jobs -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '[.items[] | select(.status.conditions == null or .status.conditions[]?.type == \"Running\" or .status.conditions[]?.type == \"Pending\")] | length'" running_jobs
        running_jobs=$((running_jobs)) # Interpret as integer

        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get jobs -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '[.items[] | select(.kind==\"Job\" and .status.conditions != null and .status.conditions[].type==\"Complete\")] | length'" completed_jobs
        completed_jobs=$((completed_jobs)) # Interpret as integer

        run_a_script "kubectl --kubeconfig ${KUBECONFIG} get jobs -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '[.items[] | select(.kind==\"Job\" and .status.conditions != null and .status.conditions[].type==\"Failed\")] | length'" failed_jobs
        failed_jobs=$((failed_jobs)) # Interpret as integer

        info_log "Current jobs statuses:  Running: ${running_jobs}   Complete: ${completed_jobs}  Failed: ${failed_jobs}"

        if [[ "${failed_jobs}" -gt 0 ]]; then
            error_log "Error detected in build service.  Errors:"

            run_a_script "kubectl --kubeconfig ${KUBECONFIG} get jobs -n ${BUILDSVC_NAMESPACE} -l \"microsoft.azureorbital/buildService\"=true -o json | jq '[.items[] | select(.kind==\"Job\" and .status.conditions != null and .status.conditions[].type==\"Failed\")] | .metadata.name'" failed_jobnames

            for failed_jobname in $failed_jobnames; do
                error_log "Failed job name: ${failed_jobname}"
            done

            exit_with_error "Error detected in build service.  See above and troubleshoot"
        fi

        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [[ $elapsed_time -ge $MAX_WAIT_SECS ]]; then
            exit_with_error "Timed out waiting for build service to finish.  Check if an error has happened, or restart deploy_k3s.sh"
        fi

        if [[ "${running_jobs}" -gt 0 ]]; then
            info_log "Found '${running_jobs}' builds still processing.  Rechecking in 3 seconds"
            sleep 3
        fi
    done

}

function main() {
    debug_log "Calculating buildservice namespace..."
    run_a_script "yq '.services.core.buildservice.serviceNamespace' \"${SPACEFX_DIR}/chart/values.yaml\"" BUILDSVC_NAMESPACE
    debug_log "...BuildService namespace calculated as '${BUILDSVC_NAMESPACE}'"

    build_service_group --service_group "platform"
    build_service_group --service_group "host"

    info_log "------------------------------------------"
    info_log "END: ${SCRIPT_NAME}"
}


main