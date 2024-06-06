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