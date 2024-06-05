#!/bin/bash
# Get the parent process ID (PPID) of the current process
current_pid=$$
bg_pids=()

# Iteratively find the parent process until we reach a non-root process
while :; do
    ppid=$(ps -o ppid= -p $current_pid)
    ppid=$(echo $ppid | tr -d ' ')  # Trim spaces

    if [ -z "$ppid" ] || [ "$ppid" -eq 1 ]; then
        echo "Reached the top of the process tree without finding a non-root process"
        exit 1
    fi

    tty=$(ps -o tty= -p $ppid)
    tty=$(echo $tty | tr -d ' ')  # Trim spaces

    euid=$(ps -o euid= -p $ppid)
    euid=$(echo $euid | tr -d ' ')  # Trim spaces

    if [ "$euid" -ne 0 ]; then
        echo "The non-root parent's TTY is: $tty"
        output_tty=$tty
        break
    fi

    current_pid=$ppid
done

if [ -z "$output_tty" ]; then
    echo "Error: Could not determine a valid TTY."
    exit 1
fi

temp_file=$(mktemp)

(
    trap "" HUP
    exec 0</dev/null
    exec 1> >(tee /dev/$output_tty > "$temp_file")
    exec 2>/dev/null
    # Redirect stdout to both the log file and the terminal
    whoami
    sleep 5
    echo "Hello, world!"
) &

bg_pids+=($!)
for pid in "${bg_pids[@]}"; do
    wait "$pid"
    return_code=$?

    echo "return code: " $return_code
done

output=$(<"$temp_file")
rm "$temp_file"

echo "Output: $output"

