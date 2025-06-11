#!/usr/bin/env bash
##############################################################################
# DeepEP installation script
##############################################################################

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd  )"
source ${SCRIPT_DIR}/common.sh

DEEPEP_SOURCE_DIR="${DEEPEP_SOURCE_DIR:-/app/DeepEP}"
DEEPEP_URL="https://github.com/deepseek-ai/DeepEP"

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
echo "DeepEP repo         : ${DEEPEP_URL}"
echo "====================================================================="

clone_or_update "${DEEPEP_URL}" "${DEEPEP_SOURCE_DIR}"

banner "Building and installing DeepEP"
pushd "${DEEPEP_SOURCE_DIR}" >/dev/null
# Build + install in one go (pip will make a wheel under the hood)
NVSHMEM_DIR="${NVSHMEM_PREFIX:-/opt/nvshmem}" \
"${PYTHON}" -m pip install --no-build-isolation --no-cache-dir .
# Optional symlink for convenience
BUILD_DIR="build/lib.linux-$(uname -m)-cpython-${PY_TAG}"
SO_NAME="deep_ep_cpp.cpython-${PY_TAG}-$(uname -m)-linux-gnu.so"
[[ -f "${BUILD_DIR}/${SO_NAME}" ]] && ln -sf "${BUILD_DIR}/${SO_NAME}" .
popd >/dev/null
