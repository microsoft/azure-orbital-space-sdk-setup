#!/bin/bash

############################################################
# Check if a command is available
############################################################
function is_cmd_available() {
    if [[ "$#" -ne 2 ]]; then
        exit_with_error "Missing a parameter.  Please use function like is_cmd_available cmd_to_check result_variable"
    fi

    local cmd_to_test=$1
    local result_variable=$2
    local cmd_result="false"
    run_a_script "whereis -b ${cmd_to_test}" check_for_cmd --no_sudo --disable_log

    if [[ $check_for_cmd != "$cmd_to_test:" ]]; then
        eval "$result_variable='true'"
    else
        eval "$result_variable='false'"
    fi
}


############################################################
# Check if prereq tool is available and if not, error with helper url
############################################################
function check_for_cmd() {
    local app_name=""
    local url=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --app)
                shift
                app_name=$1
                ;;
            --documentation-url)
                shift
                url=$1
                ;;
            *) echo "Unknown parameter '$1'"; show_help ;;
        esac
        shift
    done

    run_a_script "whereis -b ${app_name}" _check_for_cmd --no_sudo --disable_log

    if [[ $_check_for_cmd == "$cmd_to_test:" ]]; then
        # App is not available.  Throw error

        if [[ -z "${url}" ]]; then
            exit_with_error "The '${app_name}' command is not available.  Please install it and retry."
        else
            exit_with_error "The '${app_name}' command is not available.  See ${url} and retry"
        fi
    fi
}