#!/usr/bin/env bash
##############################################################################
# vLLM + PPLX + DeepEP bootstrap script
# - Creates a virtual-env with uv
# - Installs base deps, NIXL, vLLM, pplx-kernels and DeepEP
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

set -euo pipefail
trap 'echo "ERROR: Script failed on line $LINENO"; exit 1' ERR

###############################  helpers  ####################################
banner() { printf '\n========== %s ==========\n' "$*"; }

# Re-usable “uv pip install” wrapper (adds --no-cache-dir by default)
upip() { "${UV}" pip install --python "${PYTHON}" --no-cache-dir "$@"; }

# Clone the repo if missing, otherwise fast-forward to the requested branch
clone_or_update() {
  local url=$1 dir=$2 branch=${3:-main}
  if [[ -d "${dir}/.git" ]]; then
    banner "Updating $(basename "${dir}")"
    git -C "${dir}" fetch --depth=1 origin "${branch}"
    git -C "${dir}" checkout "${branch}"
    git -C "${dir}" reset --hard "origin/${branch}"
  else
    banner "Cloning $(basename "${dir}")"
    git clone --depth=1 --branch "${branch}" "${url}" "${dir}"
  fi
}

##############################  configuration  ###############################
# Locations (override via env if desired)
VLLM_SOURCE_DIR="${VLLM_SOURCE_DIR:-/app/code/vllm}"
PPLX_SOURCE_DIR="${PPLX_SOURCE_DIR:-/app/code/pplx}"
DEEPEP_SOURCE_DIR="${DEEPEP_SOURCE_DIR:-/app/code/DeepEP}"
VENV_PATH="/app/code/venv"

# Python / toolchain
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"          # e.g. 3.12
PYTHON_COMMAND="${PYTHON_COMMAND:-python${PYTHON_VERSION}}"
PY_TAG="${PYTHON_VERSION//./}"                   # 3.12 → 312 for wheel tag
UV="${UV_INSTALL_PATH:-/usr/local/bin/uv}"

# Repositories
VLLM_REPO_URL="${VLLM_REPO_URL:-https://github.com/vllm-project/vllm.git}"
VLLM_BRANCH="${VLLM_BRANCH:-main}"
PPLX_URL="https://github.com/ppl-ai/pplx-kernels"
DEEPEP_URL="https://github.com/deepseek-ai/DeepEP"
NIXL_SOURCE_DIR="${NIXL_SOURCE_DIR:-/opt/nixl}"

# Build-time env
export TORCH_CUDA_ARCH_LIST="9.0a+PTX"
export VLLM_USE_PRECOMPILED=1

#############################  sanity checks  ################################
command -v git   >/dev/null || { echo "git not found";   exit 1; }
command -v "${UV}" >/dev/null || { echo "uv not found at ${UV}"; exit 1; }

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
echo "vLLM repo / branch  : ${VLLM_REPO_URL}  (${VLLM_BRANCH})"
echo "pplx-kernels repo   : ${PPLX_URL}"
echo "DeepEP repo         : ${DEEPEP_URL}"
echo "====================================================================="

#############################  virtual-env  ##################################
banner "Creating virtual-env"
"${UV}" venv "${VENV_PATH}"
PYTHON="${VENV_PATH}/bin/python"
export PATH="${VENV_PATH}/bin:${PATH}"

banner "Installing base Python deps"
upip pandas datasets rust-just regex setuptools-scm cmake

banner "Installing NIXL"
upip "${NIXL_SOURCE_DIR}"

# --------------------------------------------------------------------------
# Ensure the venv has pip so 'python -m pip' works later (DeepEP build step)
# --------------------------------------------------------------------------
banner "Bootstrapping pip inside venv"
"${PYTHON}" -m ensurepip --upgrade
"${PYTHON}" -m pip install -U pip wheel setuptools

################################  vLLM  ######################################
clone_or_update "${VLLM_REPO_URL}" "${VLLM_SOURCE_DIR}" "${VLLM_BRANCH}"

banner "Installing vLLM (editable)"
pushd "${VLLM_SOURCE_DIR}" >/dev/null
upip -e .
popd >/dev/null

############################  pplx-kernels  ##################################
clone_or_update "${PPLX_URL}" "${PPLX_SOURCE_DIR}" "master"

banner "Building and installing pplx-kernels wheel"
pushd "${PPLX_SOURCE_DIR}" >/dev/null
"${PYTHON}" setup.py bdist_wheel
upip dist/*.whl
popd >/dev/null

################################ DeepEP ######################################
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

##############################################################################
banner "All components installed successfully – vLLM stack is ready!"
##############################################################################

