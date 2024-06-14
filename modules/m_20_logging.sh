#!/bin/bash

############################################################
# Reset the log file by renaming it with a timestamp and
# creating a new empty log file
############################################################
function _log_init() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")

    [[ ! -d "${LOG_DIR}" ]] && run_a_script "mkdir -p ${LOG_DIR}" --disable_log

    [[ -f "${LOG_FILE}" ]] && run_a_script "mv ${LOG_FILE} ${LOG_FILE}.${timestamp}" --disable_log

    run_a_script "touch ${LOG_FILE}" --disable_log
    run_a_script "chmod u=rw,g=rw,o=rw ${LOG_FILE}" --disable_log
}



############################################################
# Log a message to both stdout and the log file with a
# specified log level
############################################################
function log() {
    # log informational messages to stdout
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local log_entry="${1}"
    local received_log_level="INFO"
    local full_log_entry=""
    local log_raw=false

    if [[ -z ${log_entry} ]]; then
        return
    fi

    local configured_log_level=0
    case ${LOG_LEVEL^^} in
        ERROR)
            configured_log_level=4
            ;;
        WARN)
            configured_log_level=3
            ;;
        INFO)
            configured_log_level=2
            ;;
        DEBUG)
            configured_log_level=1
            ;;
        *)
            configured_log_level=0
            ;;
    esac

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --info)
                received_log_level="INFO"
                received_log_level_int=2
                ;;
            --debug)
                received_log_level="DEBUG"
                received_log_level_int=1
                ;;
            --warn)
                received_log_level="WARN"
                received_log_level_int=3
                ;;
            --error)
                received_log_level="ERROR"
                received_log_level_int=4
                ;;
            --trace)
                received_log_level="TRACE"
                received_log_level_int=0
                ;;
            --raw)
                log_raw=true
                ;;
        esac
        shift
    done

    if [[ ${log_raw} == false ]]; then
        full_log_entry="[${SCRIPT_NAME}] [${received_log_level}] ${timestamp}: ${log_entry}"
    else
        full_log_entry="${log_entry}"
    fi

    # Our log level isn't high enough - don't write it to the screen
    if [[ ${received_log_level_int} -lt ${configured_log_level} ]]; then
        return
    fi

    if [[ "${CURRENT_TTY}" == "${ROOT_TTY}" ]]; then
        echo "${full_log_entry}"
    fi

    if [[ "${CURRENT_TTY}" != "${ROOT_TTY}" ]] && [[ "${ROOT_TTY}" != "/dev/null" ]]; then
        echo "${full_log_entry}" > "${ROOT_TTY}"
    fi

    if [[ -n "${LOG_FILE}" ]]; then
        echo "${full_log_entry}" | tee -a "${LOG_FILE}" > /dev/null
    fi
}

# Log an informational message to stdout and the log file
function info_log() {
    log "${1}" --info
}

# Log a trace message to stdout and the log file
function trace_log() {
    log "${1}" --trace
}

# Log an debug message to stdout and the log file
function debug_log() {
    log "${1}" --debug
}

# Log an warning message to stdout and the log file
function warn_log() {
    log "${1}" --warn
}

# Log an error message to stdout and the log file
function error_log() {
    log "${1}" --error
}

# Log a critical error and exit the script with a non-zero return code
function exit_with_error() {
    # log a message to stderr and exit 1
    error_log "${1}"
    exit 1
}



############################################################
# Common starting point for all scripts to output to the log
############################################################
function _script_start(){
    info_log "START: ${SCRIPT_NAME}"
    info_log "------------------------------------------"
    info_log "Config:"
    write_parameter_to_log PWD
    write_parameter_to_log SPACEFX_DIR
    write_parameter_to_log SPACEFX_VERSION
    write_parameter_to_log SPACEFX_CHANNEL
    write_parameter_to_log LOG_FILE
    write_parameter_to_log LOG_LEVEL
}

############################################################
# Pretty writes a parameter to the log file
############################################################
function write_parameter_to_log() {
    local parameter=$1
    local parameter_value=${!1}
    max_key_length=40

    parameter_value="${parameter_value// /}" # remove blank spaces from value
    padding=$((max_key_length - ${#parameter}))
    spaces=$(printf "%-${padding}s" " ")
    info_log "${parameter}:${spaces}${parameter_value}"
}

############################################################
# Walk up the process tree to determine the root TTY we're using
############################################################
function _calculate_root_tty(){
    ROOT_TTY="$(tty)"
    CURRENT_TTY="$(tty)"

    if [[ "${CURRENT_TTY}" == "not a tty" ]]; then
        ROOT_TTY="/dev/null"
        CURRENT_TTY="/dev/null"
        return
    fi

    current_pid=$$
    # Iteratively find the parent process until we reach a non-root process
    while :; do
        ppid=$(ps -o ppid= -p $current_pid)
        ppid=$(echo $ppid | tr -d ' ')  # Trim spaces

        if [ -z "$ppid" ] || [ "$ppid" -eq 1 ]; then
            echo "Unable to calculate TTY; Reached the top of the process tree without finding a non-root process.  Will not output to the terminal."
            break
        fi

        tty=$(ps -o tty= -p $ppid)
        tty=$(echo $tty | tr -d ' ')  # Trim spaces

        euid=$(ps -o euid= -p $ppid)
        euid=$(echo $euid | tr -d ' ')  # Trim spaces

        if [ "$euid" -ne 0 ]; then
            ROOT_TTY="/dev/$tty"
            break
        fi

        current_pid=$ppid
    done

    if [[ "${ROOT_TTY}" == "/dev/?" ]]; then
        ROOT_TTY="$(tty)"
    fi

}