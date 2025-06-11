#!/usr/bin/env bash
##############################################################################
# vLLM dependencies bootstrap script
# - Creates a virtual-env with uv
# - Installs base deps and NIXL
# - Idempotent: re-runs will update existing repos instead of recloning
##############################################################################

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" && pwd  )"
source ${SCRIPT_DIR}/common.sh

##############################  configuration  ###############################
# Locations (override via env if desired)

# Repositories
NIXL_SOURCE_DIR="${NIXL_SOURCE_DIR:-/opt/nixl}"

banner "Environment summary"
echo "Python version      : ${PYTHON_VERSION}"
echo "Virtualenv path     : ${VENV_PATH}"
echo "uv binary           : ${UV}"
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
