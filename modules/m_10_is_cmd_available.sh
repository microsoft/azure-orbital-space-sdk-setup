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
    run_a_script "command -v '${cmd_to_test}'" check_for_cmd --ignore_error --no_sudo --disable_log

    if [[ -n "${check_for_cmd}" ]]; then
        cmd_result="true"
    fi

    eval "$result_variable='$cmd_result'"
}