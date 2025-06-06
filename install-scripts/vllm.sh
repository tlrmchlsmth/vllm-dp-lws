#!/usr/bin/env bash
##############################################################################
# vLLM bootstrap script
# - Installs vLLM
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

COMMON_DIR=${COMMON_DIR:-.}
source ${COMMON_DIR}/common.sh

##############################  configuration  ###############################
# Locations (override via env if desired)
VLLM_SOURCE_DIR="${VLLM_SOURCE_DIR:-/app/vllm}"

# Repositories
VLLM_REPO_URL="${VLLM_REPO_URL:-https://github.com/vllm-project/vllm.git}"
VLLM_BRANCH="${VLLM_BRANCH:-main}"
DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/tlrmchlsmth/dotfiles.git}"

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
echo "vLLM repo / branch  : ${VLLM_REPO_URL}  (${VLLM_BRANCH})"
echo "====================================================================="

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


#TODO: move this into its own script
DeepGEMM_SOURCE_DIR="/app/DeepGEMM"
DeepGEMM_URL="https://github.com/deepseek-ai/DeepGEMM"

upip cuda-python

# Repositories
VLLM_REPO_URL="${VLLM_REPO_URL:-https://github.com/vllm-project/vllm.git}"
clone_or_update "${DeepGEMM_URL}" "${DeepGEMM_SOURCE_DIR}"
pushd "${DeepGEMM_SOURCE_DIR}" >/dev/null
git submodule update --init --recursive
"${PYTHON}" setup.py install
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

