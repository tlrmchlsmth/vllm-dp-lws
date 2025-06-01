#!/usr/bin/env bash
##############################################################################
# vLLM bootstrap script
# - Installs vLLM
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

set -euo pipefail
trap 'echo "ERROR: Script failed on line $LINENO"; exit 1' ERR

###############################  helpers  ####################################
banner() { printf '\n========== %s ==========\n' "$*"; }

# Re-usable “uv pip install” wrapper (adds --no-cache-dir by default)
upip() { "${UV}" pip install --python "${PYTHON}" --no-progress --no-color --no-cache-dir "$@"; }

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
VLLM_SOURCE_DIR="${VLLM_SOURCE_DIR:-/app/vllm}"
VENV_PATH="/app/venv"

# Python / toolchain
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"          # e.g. 3.12
PYTHON_COMMAND="${PYTHON_COMMAND:-python${PYTHON_VERSION}}"
PY_TAG="${PYTHON_VERSION//./}"                   # 3.12 → 312 for wheel tag
UV="${UV_INSTALL_PATH:-/usr/local/bin/uv}"

# Repositories
VLLM_REPO_URL="${VLLM_REPO_URL:-https://github.com/vllm-project/vllm.git}"
VLLM_BRANCH="${VLLM_BRANCH:-main}"
DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/tlrmchlsmth/dotfiles.git}"

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
echo "====================================================================="

PYTHON="${VENV_PATH}/bin/python"

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

################################  Dotfiles  ######################################
banner "Installing dotfiles"
clone_or_update "${DOTFILES_REPO_URL}" "${HOME}/dotfiles"
pushd "${HOME}/dotfiles" >/dev/null

# Run dotfiles installer 
# Don't log in with GH_TOKEN_FROM_SECRET, because it takes too long.
bash ./install.sh

popd >/dev/null

##############################################################################
banner "All components installed successfully – vLLM is ready!"
##############################################################################

