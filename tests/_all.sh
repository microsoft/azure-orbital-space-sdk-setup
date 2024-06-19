#!/bin/bash
#
#  Runs all the tests
#

# Example Usage:
#
#  "bash ./tests/_all.sh"
set -e
WORKING_DIR="$(git rev-parse --show-toplevel)"

echo "Running dev_cluster.sh"
${WORKING_DIR}/tests/dev_cluster.sh
echo "dev_cluster.sh successfully passed"

echo "Running prod_cluster.sh"
${WORKING_DIR}/tests/prod_cluster.sh
echo "prod_cluster.sh successfully passed"

echo ""
echo ""
echo ""
echo "All tests successful"
set +e