source /k3s-on-host/.env

LOG_DIR="/var/log/k3s-on-host"
SCRIPT_NAME=$(basename "$0")

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

############################################################
# Reset the log file by renaming it with a timestamp and
# creating a new empty log file
############################################################
function reset_log() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    local logFile="${SCRIPT_NAME}.log"

    run_a_script "mkdir -p ${LOG_DIR}" --disable_log

    if [[ -f "${LOG_DIR}/${logFile}" ]]; then
        run_a_script "mv ${LOG_DIR}/${logFile} ${LOG_DIR}/${logFile}.${timestamp}" --disable_log
    fi
    run_a_script "touch ${LOG_DIR}/${logFile}" --disable_log
    run_a_script "chmod u=rw,g=rw,o=rw ${LOG_DIR}/${logFile}" --disable_log

    LOG_FILE="${LOG_DIR}/${logFile}"
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


    if [[ -n "${LOG_FILE}" ]]; then
        echo "${full_log_entry}" | tee -a "${LOG_FILE}"
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
# Helper function to run a script on the host
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
############################################################
function run_a_script_on_host() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
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

    run_cmd="docker exec \
                ${env_vars} \
                -ti \
                $HOST_INTERFACE_CONTAINER \
                chroot /host bash -c \"${run_script}\""


    if [[ "${log_enabled}" == true ]]; then
        trace_log "Running '${run_cmd}'..."
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
# Helper function to run a script
# args
# position 1     : the command to run.  i.e. "docker container ls"
# position 2     : the variable to return the results of the script to for further processing
# --ignore_error : allow the script to continue even if the return code is not 0
# --disable_log  : prevent the output from writing to the log and screen
############################################################
function run_a_script() {
    local timestamp=$(date "+%Y%m%d_%H%M%S")
    if [[ "$#" -eq 0 ]]; then
        exit_with_error "Missing run script to execute.  Please use function like run_a_script 'ls /'"
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
    local run_in_background=false
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ignore_error)
                ignore_error=true
                ;;
            --disable_log)
                log_enabled=false
                ;;
        esac
        shift
    done

    local run_cmd

    run_cmd="${run_script}"


    if [[ "${log_enabled}" == true ]]; then
        trace_log "Running '${run_cmd}'..."
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