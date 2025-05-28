#!/bin/bash
set -euo pipefail # Ensures script fails on errors and undefined variables

echo "=========================================================================="
echo "Starting vLLM Initialization Script"
echo "--------------------------------------------------------------------------"

# Configuration
VLLM_SOURCE_DIR="${VLLM_SOURCE_DIR:-/app/vllm}" # Default if not set externally
VENV_PATH="${VLLM_SOURCE_DIR}/.venv"           # Default if not set externally
PYTHON_COMMAND="${PYTHON_COMMAND:-python${PYTHON_VERSION}}" # Uses PYTHON_VERSION from Dockerfile ENV
UV_INSTALL_PATH="${UV_INSTALL_PATH:-/usr/local/bin/uv}" # Where to install/find uv
GIT_REPO_URL="https://github.com/vllm-project/vllm.git" # TODO: Fix
REQUIREMENTS_FILE="/app/requirements.txt"

echo "VLLM Repository URL: ${GIT_REPO_URL}"
echo "VLLM Source Directory: ${VLLM_SOURCE_DIR}"
echo "Python Virtual Environment: ${VENV_PATH}"
echo "Python command for venv: ${PYTHON_COMMAND}"
echo "uv executable path: ${UV_INSTALL_PATH}"
echo "Requirements file: ${REQUIREMENTS_FILE}"
echo "=========================================================================="

# --- Clone vLLM Repository ---
echo "Handling vLLM repository in ${VLLM_SOURCE_DIR}..."
if [ -d "${VLLM_SOURCE_DIR}/.git" ]; then
    echo "vLLM repository already exists. Skipping clone."
    # Optionally, you could add logic here to update it, e.g., git pull
else
    echo "Cloning vLLM repository from ${GIT_REPO_URL} into ${VLLM_SOURCE_DIR}..."
    git clone "${GIT_REPO_URL}" "${VLLM_SOURCE_DIR}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to clone vLLM repository."
        exit 1
    fi
fi

# --- Create Python Virtual Environment if it doesn't exist ---
echo "Setting up Python virtual environment at ${VENV_PATH}..."
if [ ! -d "${VENV_PATH}/bin" ]; then
    echo "Creating Python virtual environment using ${PYTHON_COMMAND}..."
    "${UV_INSTALL_PATH}" venv -p "${PYTHON_COMMAND}" --project "${VLLM_SOURCE_DIR}" "${VENV_PATH}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create virtual environment."
        exit 1
    fi
    echo "Virtual environment created."
else
    echo "Virtual environment already exists at ${VENV_PATH}."
fi
# Define the Python interpreter from the venv for subsequent uv commands
VENV_PYTHON="${VENV_PATH}/bin/python"
echo "--------------------------------------------------------------------------"

# --- Install dependencies from requirements.txt ---
if [ -f "${REQUIREMENTS_FILE}" ]; then
    echo "Installing dependencies from ${REQUIREMENTS_FILE} into ${VENV_PATH}..."
    "${UV_INSTALL_PATH}" pip install --python "${VENV_PYTHON}" --no-cache-dir -r "${REQUIREMENTS_FILE}"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install requirements from ${REQUIREMENTS_FILE}."
        exit 1
    fi
    echo "Dependencies installed successfully."
else
    echo "WARNING: ${REQUIREMENTS_FILE} not found. Skipping dependency installation."
fi
echo "Cleaning up ${REQUIREMENTS_FILE}"
rm ${REQUIREMENTS_FILE}
echo "--------------------------------------------------------------------------"

# --- Checkout specific Git Reference if second argument is provided ---
# This is the conditional logic you added previously.
# $1 would be the first arg to init-vllm.sh, $2 the second, etc.
# If this script is the direct command for an init container, these args come from the Pod spec.
if [ -n "${1:-}" ]; then # Using ${1:-} to avoid unbound variable error if no args
  VLLM_GIT_REF="$1"
  echo "Checking out Git Ref: ${VLLM_GIT_REF} in ${VLLM_SOURCE_DIR}"
  git -C "${VLLM_SOURCE_DIR}" checkout "${VLLM_GIT_REF}"
  if [ $? -ne 0 ]; then
      echo "ERROR: Failed to checkout Git Ref ${VLLM_GIT_REF}."
      exit 1
  fi
else
  echo "No specific Git Ref provided as first argument. Using default branch."
fi
echo "--------------------------------------------------------------------------"

# --- Install vLLM in Editable Mode ---
echo "Changing directory to ${NIXL_SOURCE_DIR} for NIXL installation..."
cd "${NIXL_SOURCE_DIR}" || { echo "ERROR: Failed to change directory to ${NIXL_SOURCE_DIR}."; exit 1; }
echo "Current directory: $(pwd)"

echo "Installing NIXL in editable mode using ${UV_INSTALL_PATH}..."
"${UV_INSTALL_PATH}" pip install --python "${VENV_PYTHON}" .
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install NIXL in editable mode."
    exit 1
fi
ls ${NIXL_SOURCE_DIR}

# --- Install vLLM in Editable Mode ---
echo "Changing directory to ${VLLM_SOURCE_DIR} for vLLM installation..."
cd "${VLLM_SOURCE_DIR}" || { echo "ERROR: Failed to change directory to ${VLLM_SOURCE_DIR}."; exit 1; }
echo "Current directory: $(pwd)"

echo "Installing vLLM in editable mode using ${UV_INSTALL_PATH}..."
# Ensure VLLM_USE_PRECOMPILED is set
echo "Setting VLLM_USE_PRECOMPILED=1"
export VLLM_USE_PRECOMPILED=1
"${UV_INSTALL_PATH}" pip install --python "${VENV_PYTHON}" -e .
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install vLLM in editable mode."
    exit 1
fi

echo "Moving Justfile into ${VLLM_SOURCE_DIR}."
mv /app/Justfile ${VLLM_SOURCE_DIR}/Justfile

echo "vLLM installed successfully in editable mode."
echo "--------------------------------------------------------------------------"
echo "vLLM Initialization Script Completed Successfully!"
echo "=========================================================================="

