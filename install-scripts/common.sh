#!/usr/bin/env bash

set -euo pipefail
trap 'echo "ERROR: Script failed on line $LINENO"; exit 1' ERR

# Python / toolchain
VENV_PATH="${VENV_PATH:-/app/venv}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"          # e.g. 3.12
PYTHON_COMMAND="${PYTHON_COMMAND:-python${PYTHON_VERSION}}"
PY_TAG="${PYTHON_VERSION//./}"                   # 3.12 → 312 for wheel tag
UV="${UV_INSTALL_PATH:-/usr/local/bin/uv}"
PYTHON="${VENV_PATH}/bin/python"
PATH="${VENV_PATH}/bin:${PATH}"

#############################  sanity checks  ################################
command -v git   >/dev/null || { echo "git not found";   exit 1; }
command -v "${UV}" >/dev/null || { echo "uv not found at ${UV}"; exit 1; }

# Build-time env
export TORCH_CUDA_ARCH_LIST="9.0a+PTX"

banner() { printf '\n========== %s ==========\n' "$*"; }

# Re-usable “uv pip install” wrapper (adds --no-cache-dir by default)
upip() { "${UV}" pip install --python "${PYTHON}" --no-progress --no-cache-dir "$@"; }

# Clone the repo if missing, otherwise fast-forward to the requested branch
clone_or_update() {
  local url=$1 dir=$2 branch=${3:-main}
  if [[ -d "${dir}/.git" ]]; then
    banner "Updating $(basename "${dir}")"
    git -C "${dir}" fetch --depth=1 origin "${branch}"
    git -C "${dir}" checkout "${branch}"
    git -C "${dir}" reset --hard "origin/${branch}"
    git -C "${dir}" submodule update --init --recursive
  else
    banner "Cloning $(basename "${dir}")"
    git clone --depth=1 --recursive --branch "${branch}" "${url}" "${dir}"
  fi
}
