#!/bin/bash
set -euo pipefail # Ensures script fails on errors and undefined variables

echo "=========================================================================="
echo "Starting vLLM Initialization Script"
echo "--------------------------------------------------------------------------"

# Configuration
VLLM_SOURCE_DIR="${VLLM_SOURCE_DIR:-/app/code/vllm}" # Default if not set externally
PPLX_SOURCE_DIR="${PPXL_SOURCE_DIR:-/app/code/pplx}"

VENV_PATH="/app/code/venv"
PYTHON_COMMAND="${PYTHON_COMMAND:-python${PYTHON_VERSION}}" # Uses PYTHON_VERSION from Dockerfile ENV
UV="${UV_INSTALL_PATH:-/usr/local/bin/uv}" # Where to install/find uv
GIT_REPO_URL="https://github.com/vllm-project/vllm.git" # TODO: Fix

echo "VLLM Repository URL: ${GIT_REPO_URL}"
echo "VLLM Source Directory: ${VLLM_SOURCE_DIR}"
echo "Python Virtual Environment: ${VENV_PATH}"
echo "Python command for venv: ${PYTHON_COMMAND}"
echo "uv executable path: ${UV}"
echo "=========================================================================="

echo "--------------------------------------------------------------------------"
echo "Creating venv at ${VENV_PATH}"
echo "--------------------------------------------------------------------------"
${UV} venv ${VENV_PATH}
PYTHON="${VENV_PATH}/bin/python"
echo "--------------------------------------------------------------------------"

# --- Install dependencies from requirements.txt ---
echo "Installing dependencies into ${VENV_PATH}..."
"${UV}" pip install --python "${PYTHON}" --no-cache-dir pandas datasets rust-just regex setuptools-scm
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install requirements from ${REQUIREMENTS_FILE}."
    exit 1
fi
echo "Dependencies installed successfully."
echo "--------------------------------------------------------------------------"

echo "--------------------------------------------------------------------------"
echo "Installing NIXL"
echo "--------------------------------------------------------------------------"
${UV} pip install --python ${PYTHON} ${NIXL_SOURCE_DIR}

# --- Install vLLM in Editable Mode ---
echo "--------------------------------------------------------------------------"
echo "Installing vllm"
echo "--------------------------------------------------------------------------"

echo "Cloning vLLM repository from ${GIT_REPO_URL} into ${VLLM_SOURCE_DIR}..."
git clone --branch pplx_intranode --single-branch "${GIT_REPO_URL}" "${VLLM_SOURCE_DIR}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone vLLM repository."
    exit 1
fi

echo "Changing directory to ${VLLM_SOURCE_DIR} for vLLM installation..."
cd "${VLLM_SOURCE_DIR}" || { echo "ERROR: Failed to change directory to ${VLLM_SOURCE_DIR}."; exit 1; }
echo "Current directory: $(pwd)"

echo "Installing vLLM in editable mode using ${UV}..."
# Ensure VLLM_USE_PRECOMPILED is set
echo "Setting VLLM_USE_PRECOMPILED=1"
export VLLM_USE_PRECOMPILED=1
"${UV}" pip install --python "${PYTHON}" -e .
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install vLLM in editable mode."
    exit 1
fi
echo "vLLM installed successfully in editable mode."

echo "--------------------------------------------------------------------------"
echo "Installing PPLX-kernels"
echo "--------------------------------------------------------------------------"
PPLX_URL="https://github.com/ppl-ai/pplx-kernels"
echo "Cloning pplx-kernels repository from ${PPLX_URL} into ${PPLX_SOURCE_DIR}..."
git clone https://github.com/ppl-ai/pplx-kernels "${PPLX_SOURCE_DIR}"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to clone pplx-kernels repository."
    exit 1
fi
echo "Changing directory to ${PPLX_SOURCE_DIR} for PPLX installation..."
cd ${PPLX_SOURCE_DIR} || { echo "ERROR: Failed to change directory to ${PPLX_SOURCE_DIR}."; exit 1; }
echo "Current directory: $(pwd)"
echo "Installing pplx-kernels in editable mode using ${UV}..."
${UV} pip install --python ${PYTHON} cmake
source ${VENV_PATH}/bin/activate
TORCH_CUDA_ARCH_LIST=9.0a+PTX ${PYTHON} setup.py bdist_wheel
${UV} pip install --python ${PYTHON} dist/*.whl
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install pplx-kernels in editable mode."
    exit 1
fi

echo "--------------------------------------------------------------------------"
echo "vLLM Initialization Script Completed Successfully!"
echo "=========================================================================="
