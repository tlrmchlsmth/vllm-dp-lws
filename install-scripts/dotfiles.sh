#!/usr/bin/env bash
##############################################################################
# TMS's dotfiles script
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd  )"
source ${SCRIPT_DIR}/common.sh

##############################  configuration  ###############################

DOTFILES_REPO_URL="${DOTFILES_REPO_URL:-https://github.com/tlrmchlsmth/dotfiles.git}"
DOTFILES_SOURCE_DIR="${HOME}/dotfiles"

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
echo "dotfiles repo       : ${DOTFILES_REPO_URL}"
echo "====================================================================="

################################  vLLM  ######################################
clone_or_update "${DOTFILES_REPO_URL}" "${DOTFILES_SOURCE_DIR}"

banner "Installing dotfiles"
pushd "${DOTFILES_SOURCE_DIR}" >/dev/null
bash install.sh
popd >/dev/null
