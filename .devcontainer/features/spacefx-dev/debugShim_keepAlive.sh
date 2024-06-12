#!/bin/bash
echo "Container started"

# Set up signal handlers
trap "echo 'SIGINT received, exiting...'; exit" SIGINT
trap "echo 'SIGTERM received, exiting...'; exit" SIGTERM
trap "echo 'SIGHUP received, exiting...'; exit" SIGHUP

tail -f /dev/null