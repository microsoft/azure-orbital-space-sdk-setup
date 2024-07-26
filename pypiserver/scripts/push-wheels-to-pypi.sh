#!/bin/bash

# Variables
WHEEL_INPUT_DIR="/var/spacedev/wheel"
PYPI_URL="https://localhost:8080/"
USERNAME="anonymous"
PASSWORD="none"

# Push all wheels in the WHEEL_INPUT_DIR to the PyPI server
push_wheels() {
    for WHEEL in "$WHEEL_INPUT_DIR"/*.whl; do
        echo "Uploading $WHEEL_FILE to PyPI server at $PYPI_URL"
        python3 -m twine upload --repository-url "$PYPI_URL" --username "$USERNAME" --password "$PASSWORD" "$WHEEL"
        echo "Upload complete"
    done
}

main() {
    push_wheels
}

main