#!/bin/bash

############################################################
# Set SUDO if we aren't already root
############################################################
function _calculate_for_sudo(){
    # Calculate if sudo is available
    CAN_SUDO=$(whereis sudo)
    if [[ -z ${CAN_SUDO} ]]; then
        # sudo not available.  Null out the parameter
        CAN_SUDO=false
    else
        if [[ $(id -u) -eq 0 ]]; then
            CAN_SUDO=false
        else
            CAN_SUDO=true
        fi
    fi
}



############################################################
# Helper function to write to a file with run a script and tee
############################################################
function write_to_file(){

    local file_contents=""
    local file=""
    local parent_dir=""
    local append=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --file)
                shift
                file=$1
                parent_dir=$(dirname $file)
                ;;
            --file_contents)
                shift
                file_contents=$1
                ;;
            --append)
                append=" -a "
                ;;
        esac
        shift
    done

    if [[ ! -d "${parent_dir}" ]]; then
        run_a_script "mkdir -p ${parent_dir}"
    fi

    debug_log "Writing to file '${file}'..."
    run_a_script "tee ${file} ${append} > /dev/null << SPACEFX_UPDATE_END
${file_contents}
SPACEFX_UPDATE_END"

    debug_log "...successfully wrote to file '${file}'"
}


############################################################
# Helper function to run a script with/without sudo
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
# --no_sudo      : prevent using sudo, even if it's available
# --background   : run the script in the background
############################################################
function run_a_script() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
    fi

    local run_script="$1"
    local  __returnVar=$2
    RETURN_CODE=""
    OUTPUT_RESULTS=""

    # We're passing flags and not a return value.  Reset the return variable here
    if [[ "${__returnVar:0:2}" == "--" ]]; then
        __returnVar=""
    fi

    local log_enabled=true
    local log_results_enabled=true
    local ignore_error=false
    local run_in_background=false
    local returnResult=""
    local bg_pids=()
    local bg_pid=""
    local no_sudo=false
    local run_cmd

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ignore_error)
                ignore_error=true
                ;;
            --disable_log)
                log_enabled=false
                ;;
            --no_log_results)
                log_results_enabled=false
                ;;
            --background)
                run_in_background=true
                ;;
            --no_sudo)
                no_sudo=true
                ;;
            *) if [[ "${__returnVar:0:2}" == "--" ]]; then
                    echo "Unknown parameter '$1'"
                    exit 1
               fi
               ;;
        esac
        shift
    done

    # Calculate if sudo is available and needed
    if [[ ${CAN_SUDO} == true ]] && [[ ${no_sudo} == false ]]; then
        run_cmd="sudo --preserve-env --set-home ${run_script}"
    else
        run_cmd="${run_script}"
    fi


    # Setup a temp file to capture the output from the command
    script_temp_file=$(mktemp)
    script_temp_std_file="${script_temp_file}.stdout"
    script_temp_exit_code="${script_temp_file}.exitcode"

    touch $script_temp_file
    touch $script_temp_std_file
    touch $script_temp_exit_code


    [[ "${log_enabled}" == true ]] && debug_log "Running '${run_cmd}' (log file: ${script_temp_std_file}; exit code: ${script_temp_exit_code})..."

    (
        trap "" HUP
        exec 0</dev/null
        exec 1> >(tee $ROOT_TTY > "$script_temp_std_file")
        exec 2>&1
        eval "${run_cmd}" > $script_temp_file
        echo $? > $script_temp_exit_code
    ) &

    # Save the PID to a variable so we can process it
    bg_pid=$!

    if [[ "${log_enabled}" == true ]]; then
        tail -f "$script_temp_std_file" &
        tail_pid=$!
    fi


    # The user requested to run the script in the background.  Return the PID, the output file, and exit
    if [[ "${run_in_background}" == true ]]; then
        if [[ -n ${__returnVar} ]]; then
            eval $__returnVar="'$bg_pid'"
            OUTPUT_RESULTS=$script_temp_file
        fi
        return
    fi

    # Add the PID to the array so we can wait for it to finish
    bg_pids+=($bg_pid)
    for pid in "${bg_pids[@]}"; do
        wait "$pid"
        if [[ -n "${tail_pid}" ]]; then
            kill "${tail_pid}" > /dev/null
            tail_pid=""
        fi
        RETURN_CODE=$(cat $script_temp_exit_code)
    done

    [[ "${log_enabled}" == true ]] && debug_log "...'${run_cmd}' Exit code: ${RETURN_CODE}"



    returnResult=$(<"$script_temp_file")
    [[ "${log_enabled}" == true ]] && [[ "${log_results_enabled}" == true ]] && debug_log "...'${run_cmd}' Result: ${returnResult}"
    # Read the results of the script into the return variable
    if [[ -n ${__returnVar} ]]; then
        eval $__returnVar="'$returnResult'"
    fi

    if [[ $RETURN_CODE -gt 0 ]] && [[ "${ignore_error}" == false ]]; then
        exit_with_error "Script failed.  Received return code of '${RETURN_CODE}'.  Command ran: '${run_script}'.  Output: '${script_temp_file}'   See previous errors and retry"
    fi

    # Cleanup by removing the temp file
    [[ -f "$script_temp_file" ]] && rm "$script_temp_file"
    [[ -f "$script_temp_std_file" ]] && rm "$script_temp_std_file"
    [[ -f "$script_temp_exit_code" ]] && rm "$script_temp_exit_code"

}



############################################################
# Helper function to run a script on the host via the host_interface container
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
############################################################
function run_a_script_on_host() {
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
    fi

    if [[ "${SPACESDK_CONTAINER}" != "true" ]]; then
        exit_with_error "run_a_script_on_host can only be executed from a container."
    fi

    local run_script="$1"
    local  __returnVar=$2
    RETURN_CODE=""
    # We're passing flags and not a return value.  Reset the return variable here
    if [[ "${__returnVar:0:2}" == "--" ]]; then
        __returnVar=""
    fi

    local log_enabled=true
    local ignore_error=false
    local env_vars=""
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ignore_error)
                ignore_error=true
                ;;
            --disable_log)
                log_enabled=false
                ;;
            --env)
                shift
                env_vars="${env_vars} --env $1"
                ;;
        esac
        shift
    done

    local run_cmd

    run_cmd="docker run \
        --quiet \
        --privileged \
        --tty \
        --rm \
        --cap-add=SYS_CHROOT \
        --name $HOST_INTERFACE_CONTAINER \
        --net=host --pid=host --ipc=host \
        --volume /:/host \
        $HOST_INTERFACE_CONTAINER_BASE \
        chroot /host bash --login -c \"${run_script}\""


    if [[ "${log_enabled}" == true ]]; then
        trace_log "Running '${run_cmd}' on host..."
    fi

    returnResult=$(eval "${run_cmd}" )

    sub_exit_code=${PIPESTATUS[0]}
    RETURN_CODE=${sub_exit_code}
    if [[ -n ${__returnVar} ]]; then
        eval $__returnVar="'$returnResult'"
    fi

    if [[ "${log_enabled}" == true ]]; then
        trace_log "...'${run_cmd}' Exit code: ${sub_exit_code}"
        trace_log "...'${run_cmd}' Result: ${returnResult}"
    fi

    if [[ "${ignore_error}" == true ]]; then
        return
    fi

    if [[ $sub_exit_code -gt 0 ]]; then
        exit_with_error "Script failed.  Received return code of '${sub_exit_code}'.  Command ran: '${run_script}'.  See previous errors and retry"
    fi
}

############################################################
# Parses a base64-encoded json string row and returns the value requested
############################################################
function parse_json_line() {
    local base_64_encoded=""
    local property=""
    local result_variable=""
    local result_value=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --json)
                shift
                base_64_encoded=$1
                ;;
            --property)
                shift
                property=$1
            ;;
            --result)
                shift
                result_variable=$1
                ;;
            *) echo "Unknown parameter '$1'"; show_help ;;
        esac
        shift
    done

    if [[ -z "${base_64_encoded}" ]]; then
        exit_with_error "Missing parameter --json"
    fi

    if [[ -z "${property}" ]]; then
        exit_with_error "Missing parameter --property"
    fi

    if [[ -z "${result_variable}" ]]; then
        exit_with_error "Missing parameter --result_variable"
    fi

    eval "$result_variable=''"

    result_value=$(echo $base_64_encoded | base64 -d | jq -r "${property}")

    eval "$result_variable='$result_value'"
}