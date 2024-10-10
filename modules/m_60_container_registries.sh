#!/bin/bash

############################################################
# Given a container registry and a container image, build the full image name to include any prefixing
############################################################
function get_image_name(){

    local registry=""
    local repo=""
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --registry)
                shift
                registry=$1
                ;;
            --repo)
                shift
                repo=$1
                ;;
            --result)
                shift
                returnResult=$1
                ;;
            *)
                echo "Unknown parameter '$1'"
                exit 1
               ;;
        esac
        shift
    done

    if [[ -z "${container_registry}" ]] || [[ -z "${repo}" ]]  || [[ -z "${returnResult}" ]]; then
        exit_with_error "Missing a parameter.  Please use function like check_for_repo_prefix --registry \"registry\" --repo \"repo\" --result \"returnResult\".  Please supply all parameters."
    fi

    check_for_repo_prefix_for_registry --registry "${registry}" --result repo_prefix

    if [[ -n "${repo_prefix}" ]]; then
        debug_log "Repository Prefix '${repo_prefix}' found for ${registry}.  Returning '${repo_prefix}/${repo}'"
        eval "$returnResult='${registry}/${repo_prefix}/${repo}'"
    else
        debug_log "No Repository Prefix found for ${registry}.  Returning '${repo}'"
        eval "$returnResult='${registry}/${repo}'"
    fi

}

############################################################
# Check if we need to add a prefix to the repo based on the supplied container registry
############################################################
function check_for_repo_prefix_for_registry(){

    local registry=""
    local repo=""
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --registry)
                shift
                registry=$1
                ;;
            --result)
                shift
                returnResult=$1
                ;;
            *)
                echo "Unknown parameter '$1'"
                exit 1
               ;;
        esac
        shift
    done

    if [[ -z "${registry}" ]] || [[ -z "${returnResult}" ]]; then
        exit_with_error "Missing a parameter.  Please use function like check_for_repo_prefix --registry \"registry\" --repo \"repo\" --result \"returnResult\".  Please supply all parameters."
    fi

    if [[ ! -f "${SPACEFX_DIR}/tmp/config/spacefx-config.json" ]]; then
        warn_log "Configuration file not found.  Running '_generate_spacefx_config_json' to generate it."
        _generate_spacefx_config_json
    fi

    # Check if our destination repo has a repositoryPrefix
    run_a_script "jq -r '.config.containerRegistries[] | select(.url == \"${registry}\") | if (has(\"repositoryPrefix\")) then .repositoryPrefix else \"\" end' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" repo_prefix

    if [[ -n "${repo_prefix}" ]]; then
        debug_log "Repository Prefix '${repo_prefix}' found for ${registry}."
        eval "$returnResult='${repo_prefix}'"
    else
        debug_log "No Repository Prefix found for ${registry}."
        eval "$returnResult=''"
    fi

}


############################################################
# Check if we need to add a prefix to the repo based on the supplied container registry
############################################################
function check_for_repo_prefix(){

    local registry=""
    local repo=""
    local returnResult=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --registry)
                shift
                registry=$1
                ;;
            --repo)
                shift
                repo=$1
                ;;
            --result)
                shift
                returnResult=$1
                ;;
            *)
                echo "Unknown parameter '$1'"
                exit 1
               ;;
        esac
        shift
    done

    if [[ -z "${container_registry}" ]] || [[ -z "${repo}" ]]  || [[ -z "${returnResult}" ]]; then
        exit_with_error "Missing a parameter.  Please use function like check_for_repo_prefix --registry \"registry\" --repo \"repo\" --result \"returnResult\".  Please supply all parameters."
    fi

    check_for_repo_prefix_for_registry --registry "${registry}" --result repo_prefix

    if [[ -n "${repo_prefix}" ]]; then
        # Check if we already prefixed the repo name
        if [[ "${repo}" == "$repo_prefix"* ]]; then
            debug_log "Repository Prefix '${repo_prefix}' for ${registry} is already applied to '${repo}'.  Nothing to do"
            eval "$returnResult='${repo}'"
        else
            debug_log "Repository Prefix '${repo_prefix}' found for ${registry}.  Returning '${repo_prefix}/${repo}'"
            eval "$returnResult='${repo_prefix}/${repo}'"
        fi
    else
        debug_log "No Repository Prefix found for ${registry}.  Returning '${repo}'"
        eval "$returnResult='${repo}'"
    fi

}


############################################################
# Get the container tag value based on the channel we're using
############################################################
function calculate_tag_from_channel() {

    local tag=""
    local returnResult=""
    local return_tag=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --tag)
                shift
                tag=$1
                ;;
            --result)
                shift
                returnResult=$1
                ;;
            *)
                echo "Unknown parameter '$1'"
                exit 1
               ;;
        esac
        shift
    done

    if [[ -z "${tag}" ]] || [[ -z "${returnResult}" ]]; then
        exit_with_error "Missing a parameter.  Please use function like calculate_tag_from_channel --tag \"tag\" --result \"result\".  Please supply all parameters."
    fi

    if [[ "${SPACEFX_CHANNEL}" == "nightly" ]]; then
        return_tag="${tag}-nightly"
    fi

    if [[ "${SPACEFX_CHANNEL}" == "stable" ]]; then
        return_tag="${tag}"
    fi

    if [[ "${SPACEFX_CHANNEL}" == "rc" ]]; then
        return_tag="${tag}-rc"
    fi

    eval "$returnResult='$return_tag'"
}


############################################################
# Find the first container registry with push access enabled
############################################################
function get_registry_with_push_access() {
    local return_result_var=$1
    if [[ -z "${return_result_var}" ]]; then
        exit_with_error "Please supply a return variable name for results"
    fi
    run_a_script "jq -r '.config.containerRegistries[] | select(.push_enabled == true) | .url' ${SPACEFX_DIR}/tmp/config/spacefx-config.json | head -n 1" container_registry_with_push_access --ignore_error --disable_log
    eval "$return_result_var='$container_registry_with_push_access'"
}

############################################################
# Pull the registry image locally
############################################################
function find_registry_for_image(){
    local container_image="$1"
    local return_result_var=$2
    if [[ -z "${return_result_var}" ]]; then
        exit_with_error "Please supply a return variable name for results"
    fi

    info_log "Locating registry for '${container_image}'..."
    run_a_script "jq -r '.config.containerRegistries[] | select(.pull_enabled == true) | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" container_registries --disable_log

    REGISTRY_IMAGE_NAME=""

    for row in $container_registries; do
        parse_json_line --json "${row}" --property ".url" --result container_registry
        parse_json_line --json "${row}" --property ".login_enabled" --result login_enabled
        parse_json_line --json "${row}" --property ".login_username_file" --result login_username_file
        parse_json_line --json "${row}" --property ".login_password_file" --result login_password_file

        check_for_repo_prefix --registry "${container_registry}" --repo "${container_image}" --result _find_registry_for_image_repo

        info_log "Checking container registry '${container_registry}' for image '${_find_registry_for_image_repo}'..."

        if [[ "${login_enabled}" == "true" ]]; then
            login_to_container_registry --container_registry "${container_registry}" --container_registry_username_file "${login_username_file}" --container_registry_password_file "${login_password_file}"
        fi

        debug_log "Running 'regctl image manifest ${container_registry}/${_find_registry_for_image_repo}'"
        run_a_script "regctl image manifest ${container_registry}/${_find_registry_for_image_repo}" _find_registry_for_image_result --ignore_error --disable_log
        debug_log "_find_registry_for_image_result:"
        debug_log "${_find_registry_for_image_result}"

        
        if [[ "${_find_registry_for_image_result}" == *"unauthorized"* ]]; then
            exit_with_error "Unauthorized to access image to container registry '${container_registry}'.  Please login with docker login '${container_registry}', regctl registry login '${container_registry}' --user <username> --pass <password>, or use the config login_username_file and login_password_file configuration options"
        fi

        if [[ "${RETURN_CODE}" -eq 0 ]]; then
            info_log "...image '${container_image}' FOUND in container registry '${container_registry}' (as '${_find_registry_for_image_repo}')"
            REGISTRY_IMAGE_NAME="${container_registry}"
            break;
        else
            info_log "...image ${container_image}' ('${_find_registry_for_image_repo}') NOT FOUND in container registry '${container_registry}'"
        fi
    done

    eval "$return_result_var='$REGISTRY_IMAGE_NAME'"
}

############################################################
# Login to container registry
############################################################
function login_to_container_registry(){
    info_log "START: ${FUNCNAME[0]}"

    local container_registry=""
    local container_registry_username_file=""
    local container_registry_password_file=""

    local is_logged_in=false

    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --container_registry)
            shift
            container_registry=$1
            ;;
        --container_registry_username_file)
            shift
            container_registry_username_file=$1
            ;;
        --container_registry_password_file)
            shift
            container_registry_password_file=$1
            ;;
        esac
        shift
    done

    [[ -z "${container_registry}" ]] && exit_with_error "--container_registry empty.  Please supply a container registry to login to"

    info_log "container_registry_username_file '${container_registry_username_file}'..."

    is_cmd_available "docker" HAS_DOCKER

    if [[ "${HAS_DOCKER}" == true ]]; then
        trace_log "Docker detected.  Checking if we're already logged in to '${container_registry}'..."

        if [[ -f "${HOME}/.docker/config.json" ]]; then
            run_a_script "jq -r '.auths | has(\"${container_registry}\")' ${HOME}/.docker/config.json" is_logged_in
        fi

        if [[ "${is_logged_in}" == false ]]; then
            run_a_script "docker logout ${container_registry}" --ignore_error --disable_log
            run_a_script "docker logout ${container_registry}" --ignore_error --disable_log --no_sudo

            [[ -z "${container_registry_username_file}" ]] && exit_with_error "--container_registry_username_file empty. Please supply a container registry username file to login to"
            [[ -z "${container_registry_password_file}" ]] && exit_with_error "--container_registry_password_file empty.  Please supply a container registry password file to login to"
            [[ ! -f "${container_registry_username_file}" ]] && exit_with_error "Unable to login to '${container_registry}'.  Username file '${container_registry_username_file}' not found"
            [[ ! -f "${container_registry_password_file}" ]] && exit_with_error "Unable to login to '${container_registry}'.  Password file '${container_registry_password_file}' not found"

            run_a_script "cat ${container_registry_username_file}" container_registry_username --disable_log
            run_a_script "cat ${container_registry_password_file}" container_registry_password --disable_log
            run_a_script "docker login ${container_registry} --username '${container_registry_username}' --password '${container_registry_password}'" --disable_log
            run_a_script "docker login ${container_registry} --username '${container_registry_username}' --password '${container_registry_password}'" --disable_log --no_sudo

            is_logged_in=true
        else
            info_log "Already logged in to '${container_registry}' with Docker."
            info_log "END: ${FUNCNAME[0]}"
            return
        fi
    fi

    # This will allow us to login with regctl if docker is not available
    is_cmd_available "regctl" HAS_REGCTL
    if [[ "${HAS_REGCTL}" == true ]]; then
        trace_log "Regctl detected.  Checking if we're already logged in to '${container_registry}'..."

        if [[ -f "${HOME}/.regctl/config.json" ]]; then
            run_a_script "jq -r '.hosts | has(\"${container_registry}\")' ${HOME}/.regctl/config.json" is_logged_in --disable_log
        fi

        if [[ "${is_logged_in}" == false ]]; then
            run_a_script "regctl registry logout ${container_registry}" --ignore_error --disable_log
            run_a_script "regctl registry logout ${container_registry}" --ignore_error --disable_log --no_sudo

            [[ -z "${container_registry_username_file}" ]] && exit_with_error "--container_registry_username_file empty. Please supply a container registry username file to login to"
            [[ -z "${container_registry_password_file}" ]] && exit_with_error "--container_registry_password_file empty.  Please supply a container registry password file to login to"
            [[ ! -f "${container_registry_username_file}" ]] && exit_with_error "Unable to login to '${container_registry}'.  Username file '${container_registry_username_file}' not found"
            [[ ! -f "${container_registry_password_file}" ]] && exit_with_error "Unable to login to '${container_registry}'.  Password file '${container_registry_password_file}' not found"

            run_a_script "cat ${container_registry_username_file}" container_registry_username --disable_log
            run_a_script "cat ${container_registry_password_file}" container_registry_password --disable_log
            run_a_script "regctl registry login ${container_registry} --user '${container_registry_username}' --pass '${container_registry_password}'" --disable_log
            run_a_script "regctl registry login ${container_registry} --user '${container_registry_username}' --pass '${container_registry_password}'" --disable_log --no_sudo

            is_logged_in=true
        else
            trace_log "Already logged in to '${container_registry}' with Regctl."
        fi
    fi


    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Push a local image to a repository
############################################################
function push_to_repository(){
    info_log "START: ${FUNCNAME[0]}"

    local image_name=""

    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image_name=$1
            ;;
        esac
        shift
    done

    info_log "Pushing '${image_name}'..."

    run_a_script "docker push ${image_name}"
    run_a_script "regctl image mod ${image_name} --replace --label-to-annotation" --disable_log
    info_log "...successfully pushed '${image_name}'"

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Push a local image to a repository
############################################################
function gen_and_push_manifest(){
    info_log "START: ${FUNCNAME[0]}"

    local image_name=""
    local _annotations=()
    local _gen_manifest_annotations=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image_name=$1
            ;;
        --annotation)
            shift
            _annotations+=($1)
            ;;
        esac
        shift
    done

    run_a_script "jq -r '.config | has(\"annotations\")' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_annotations --disable_log

    if [[ "${has_annotations}" == "true" ]]; then
        run_a_script "jq -r '.config.annotations[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" gh_annotations --disable_log

        for gh_annotation in $gh_annotations; do
            parse_json_line --json "${gh_annotation}" --property ".annotation" --result decoded_annotation
            _annotations+=("${decoded_annotation}")
        done
    fi

    for annotationpart in "${_annotations[@]}"; do
        _gen_manifest_annotations="${_gen_manifest_annotations} --annotation=${annotationpart}"
    done



    info_log "Checking if prior manifest '${image_name}' exists..."
    run_a_script "regctl manifest get ${image_name} --format '{{json .}}'" manifest_entries --ignore_error

    if [[ -z "${manifest_entries}" ]]; then
        info_log "...manifest not found.  Creating '${image_name}'..."
        run_a_script "regctl index create ${image_name} \
                                        ${annotation_string} \
                                        --media-type application/vnd.docker.distribution.manifest.list.v2+json"

        info_log "...repulling the manifest..."
        run_a_script "regctl manifest get ${image_name} --format '{{json .}}'" manifest_entries --ignore_error

        info_log "...successfully created index '${image_name}'."
    fi

    add_annotation_to_image --image "${image_name}" --full_annotation_string "${_gen_manifest_annotations}"


    info_log "Manifest '${image_name}' found"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Set annotations on an image by replacing any existing annotations
############################################################
function set_annotation_to_image(){
    info_log "START: ${FUNCNAME[0]}"

    local image_name=""
    local annotations=()
    local annotation_string=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image_name=$1
            ;;
        --annotation)
            shift
            annotations+=($1)
            ;;
        --full_annotation_string)
            shift
            annotation_string=$1
        esac
        shift
    done


    if [[ -z "${annotation_string}" ]]; then

        run_a_script "jq -r '.config | has(\"annotations\")' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_annotations --disable_log

        if [[ "${has_annotations}" == "true" ]]; then
            run_a_script "jq -r '.config.annotations[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" gh_annotations --disable_log

            for gh_annotation in $gh_annotations; do
                parse_json_line --json "${gh_annotation}" --property ".annotation" --result decoded_annotation
                annotations+=("${decoded_annotation}")
            done
        fi

        for annotationpart in "${annotations[@]}"; do
            if [[ -n "${annotationpart}" ]]; then
                annotation_string="${annotation_string} --annotation=${annotationpart}"
            fi
        done
    fi

    info_log "Checking if prior manifest '${image_name}' exists..."
    run_a_script "regctl manifest head ${image_name}" manifest_entries --ignore_error

    if [[ -n "${manifest_entries}" ]]; then
        info_log "...manifest found.  Setting annotations to '${image_name}'..."
        run_a_script "regctl image mod ${image_name} ${annotation_string}  --replace" --disable_log
        info_log "...successfully set annotations for '${image_name}'."
    else
        info_log "Image '${image_name}' not found.  Nothing to do"
    fi


    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Set annotations on an image by replacing any existing annotations
############################################################
function remove_annotations_from_image(){
    info_log "START: ${FUNCNAME[0]}"

    local image_name=""
    local annotation_string=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image_name=$1
            ;;
        esac
        shift
    done


    run_a_script "regctl manifest get ${image_name} --format '{{json .}}' | jq -r '.annotations | to_entries[] | @base64 '" current_annotations --ignore_error

    for annotation in $current_annotations; do
        parse_json_line --json "${annotation}" --property ".key" --result annotation_key
        parse_json_line --json "${annotation}" --property ".value" --result annotation_value

        # Remove the annotation by setting it to empty
        annotation_string="${annotation_string} --annotation=${annotation_key}="
    done

    if [[ -n "${annotation_string}" ]]; then
        info_log "Removing annotations from '${image_name}'..."
        run_a_script "regctl image mod ${image_name} ${annotation_string}  --replace" --disable_log
        info_log "...successfully removed annotations for '${image_name}'."
    else
        info_log "No annotations found for '${image_name}'.  Nothing to do"
    fi


    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Add an annotation to an image while preserving any previous annotations
############################################################
function add_annotation_to_image(){
    info_log "START: ${FUNCNAME[0]}"

    local image_name=""
    local _add_annotations=()
    local _add_annotation_string=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image_name=$1
            ;;
        --annotation)
            shift
            _add_annotations+=($1)
            ;;
        --full_annotation_string)
            shift
            _add_annotation_string=$1
        esac
        shift
    done


    run_a_script "jq -r '.config | has(\"annotations\")' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_annotations --disable_log

    if [[ "${has_annotations}" == "true" ]]; then
        run_a_script "jq -r '.config.annotations[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" gh_annotations --disable_log

        for gh_annotation in $gh_annotations; do
            parse_json_line --json "${gh_annotation}" --property ".annotation" --result decoded_annotation
            _add_annotations+=("${decoded_annotation}")
        done
    fi


    info_log "Checking if prior manifest '${image_name}' exists..."
    run_a_script "regctl manifest head ${image_name}" manifest_entries --ignore_error

    if [[ -z "${manifest_entries}" ]]; then
        info_log "Image '${image_name}' not found.  Nothing to do"
        info_log "END: ${FUNCNAME[0]}"
        return
    fi

    info_log "...manifest found.  Querying for current annotations to '${image_name}'..."

    run_a_script "regctl manifest get ${image} --format '{{json .}}' | jq -r '.annotations | to_entries[] | @base64 '" current_annotations --ignore_error

    for annotation in $current_annotations; do
        parse_json_line --json "${annotation}" --property ".key" --result annotation_key
        parse_json_line --json "${annotation}" --property ".value" --result annotation_value
        _add_annotation_string="${_add_annotation_string} --annotation=${prev_annotationpart}"
    done

    for annotationpart in "${_add_annotations[@]}"; do
        if [[ -n "${annotationpart}" ]]; then
            _add_annotation_string="${_add_annotation_string} --annotation=${annotationpart}"
        fi
    done

    trace_log "Full annotation string: ${_add_annotation_string}"

    set_annotation_to_image --image "${image_name}" --full_annotation_string "${_add_annotation_string}"

    info_log "...successfully added annotations for '${image_name}'."

    info_log "END: ${FUNCNAME[0]}"
}

############################################################
# Add new container image to manifest
############################################################
function add_image_to_manifest(){
    info_log "START: ${FUNCNAME[0]}"

    local main_image_tag=""
    local child_image_tag=""
    local container_registry=""
    local repository=""
    local annotations=()

    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --container_registry)
            shift
            container_registry=$1
            ;;
        --repository)
            shift
            repository=$1
            ;;
        --main_image_tag)
            shift
            main_image_tag=$1
            ;;
        --child_image_tag)
            shift
            child_image_tag=$1
            ;;
         --annotation)
            shift
            annotations+=($1)
            ;;
        esac
        shift
    done

    local annotation_string=""

    run_a_script "jq -r '.config | has(\"annotations\")' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_annotations --disable_log

    if [[ "${has_annotations}" == "true" ]]; then
        run_a_script "jq -r '.config.annotations[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" gh_annotations --disable_log

        for gh_annotation in $gh_annotations; do
            parse_json_line --json "${gh_annotation}" --property ".annotation" --result decoded_annotation
            annotations+=("${decoded_annotation}")
        done
    fi

    for annotationpart in "${annotations[@]}"; do
        annotation_string="${annotation_string} --desc-annotation=${annotationpart}"
    done


    info_log "Adding '${container_registry}/${repository}:${child_image_tag}' to '${container_registry}/${repository}:${main_image_tag}'"
    run_a_script "regctl index add ${container_registry}/${repository}:${main_image_tag} --ref ${container_registry}/${repository}:${child_image_tag} ${annotation_string}"
    info_log "...successfully added '${container_registry}/${repository}:${child_image_tag}' to '${container_registry}/${repository}:${main_image_tag}'"



    info_log "END: ${FUNCNAME[0]}"
}



############################################################
# Update a parent image to redirect to a destination image
############################################################
function add_redirect_to_image(){
    info_log "START: ${FUNCNAME[0]}"

    local image=""
    local destination_image=""
    local annotations=()

    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --image)
            shift
            image=$1
            ;;
        --destination_image)
            shift
            destination_image=$1
            ;;
         --annotation)
            shift
            annotations+=($1)
            ;;
        esac
        shift
    done

    local annotation_string=""

    run_a_script "jq -r '.config | has(\"annotations\")' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" has_annotations --disable_log

    if [[ "${has_annotations}" == "true" ]]; then
        run_a_script "jq -r '.config.annotations[] | @base64' ${SPACEFX_DIR}/tmp/config/spacefx-config.json" gh_annotations --disable_log

        for gh_annotation in $gh_annotations; do
            parse_json_line --json "${gh_annotation}" --property ".annotation" --result decoded_annotation
            annotations+=("${decoded_annotation}")
        done
    fi

    for annotationpart in "${annotations[@]}"; do
        annotation_string="${annotation_string} --desc-annotation=${annotationpart}"
    done

    info_log "Adding redirect from '${image}' to '${destination_image}' for '${ARCHITECTURE}'"

    debug_log "Querying for manifest for parent image '${image}'..."
    run_a_script "regctl manifest get ${image} --format '{{json .}}'" image_manifest


    debug_log "Checking for '${ARCHITECTURE}' in manifest..."
    run_a_script "jq -r '.manifests[] | select(.platform.architecture == \"${ARCHITECTURE}\") | .digest'  <<< \${image_manifest}" arch_digest

    if [[ -n "${arch_digest}" ]]; then
        debug_log "Removing previous redirect for '${ARCHITECTURE}'..."
        run_a_script "regctl index delete ${image} --digest ${arch_digest}"
        debug_log "...successfull removed previous redirect for '${ARCHITECTURE}'."
    else
        debug_log "No previous redirects found for '${ARCHITECTURE}'."
    fi

    info_log "Adding '${destination_image}' to '${image}'"
    run_a_script "regctl index add ${image} --ref ${destination_image} ${annotation_string} --desc-platform=linux/${ARCHITECTURE}"
    info_log "...successfully added '${destination_image}' to '${image}'"

    info_log "END: ${FUNCNAME[0]}"
}


############################################################
# Convert the filename to a repository name for dynamically loading / finding build artifacts
############################################################
function calculate_repo_name_from_filename() {
    local filename=""
    local return_result_var=""
    while [[ "$#" -gt 0 ]]; do
        case $1 in
        --filename)
            shift
            filename=$1
            ;;
        --result)
            shift
            return_result_var=$1
            ;;
        esac
        shift
    done

    if [[ -z "${filename}" ]]; then
        exit_with_error "Please supply a filename to convert to a repository"
    fi

    if [[ -z "${return_result_var}" ]]; then
        exit_with_error "Please supply a return variable name for results"
    fi

    run_a_script "basename ${filename}" base_filename --disable_log

    trace_log "Converting filename '${base_filename}' to a repository name..."

    # Get the filename and extension of the filename
    local return_dest_repo_suffix="${base_filename}"
    local extension="${base_filename##*.}"


    # Convert to lowercase
    return_dest_repo_suffix="${return_dest_repo_suffix,,}"
    extension="${extension,,}"

    # Remove the extension
    return_dest_repo_suffix=${return_dest_repo_suffix//"${extension}"/}

    # Check if we're pushing a wheel and if so, convert the dashes to periods
    if [[ $extension == "whl" ]]; then
        return_dest_repo_suffix=${return_dest_repo_suffix//-/.}
    fi

    # Remove any references to spacefx version embedded from dotnet (which adds the -a)
    return_dest_repo_suffix=${return_dest_repo_suffix//"${SPACEFX_VERSION}-a"/}

    # Remove any references to spacefx version
    return_dest_repo_suffix=${return_dest_repo_suffix//"${SPACEFX_VERSION}"/}


    # Update any double periods to a single periods
    return_dest_repo_suffix=${return_dest_repo_suffix//../.}

    # Check if the last character is a period and if so, remove it
    if [[ "${return_dest_repo_suffix: -1}" == "." ]]; then
        return_dest_repo_suffix="${return_dest_repo_suffix%?}"
    fi

    # Replace all periods "." with slashes "/"
    return_dest_repo_suffix=${return_dest_repo_suffix//./\/}

    trace_log "...returning calculated repository: 'buildartifacts/${extension}/${return_dest_repo_suffix}'"

    eval "$return_result_var='buildartifacts/${extension}/${return_dest_repo_suffix}'"
}