#!/usr/bin/env bash
##############################################################################
# PPLX installation script
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd  )"
source ${SCRIPT_DIR}/common.sh

PPLX_SOURCE_DIR="${PPLX_SOURCE_DIR:-/app/pplx}"
PPLX_URL="https://github.com/ppl-ai/pplx-kernels"

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
echo "pplx-kernels repo   : ${PPLX_URL}"
echo "====================================================================="

############################  pplx-kernels  ##################################
clone_or_update "${PPLX_URL}" "${PPLX_SOURCE_DIR}" "master"

banner "Building and installing pplx-kernels wheel"
pushd "${PPLX_SOURCE_DIR}" >/dev/null
"${PYTHON}" setup.py bdist_wheel
upip dist/*.whl
popd >/dev/null

