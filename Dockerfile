# Dockerfile for vLLM development
# Use a CUDA base image.
FROM nvidia/cuda:12.8.1-devel-ubuntu24.04

WORKDIR /app

ENV PYTHON_VERSION=3.12
ENV UCX_VERSION=1.18.1
ENV UCX_HOME=/opt/ucx
ENV CUDA_HOME=/usr/local/cuda/
ENV GDRCOPY_VERSION=2.5
ENV GDRCOPY_HOME=/usr/local
ENV NIXL_VERSION="0.1.1"
ENV NIXL_SOURCE_DIR=/opt/nixl
ENV NIXL_PREFIX=/usr/local/nixl

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Python and related tools
    python${PYTHON_VERSION} \
    python${PYTHON_VERSION}-venv \
    python3-pip \
    python3-pybind11 \
    python${PYTHON_VERSION}-dev \
    # Common dev tools
    git \
    wget curl \
    ca-certificates \
    htop \
    iputils-ping \
    net-tools \
    vim ripgrep bat clangd fuse fzf \
    nodejs npm clang fd-find xclip \
    zsh \
    # Build tools for UCX and other source compilations
    build-essential \
    wget \
    autoconf \
    automake \
    libtool \
    pkg-config \
    meson \
    ninja-build \
    # Other potential UCX dependencies
    libnuma-dev \
    # Cleanup
    && rm -rf /var/lib/apt/lists/*    
    
# Mellanox OFED (latest)
RUN wget -qO - https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | apt-key add -
RUN cd /etc/apt/sources.list.d/ \
    && wget https://linux.mellanox.com/public/repo/mlnx_ofed/latest/ubuntu24.04/mellanox_mlnx_ofed.list
    
RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
    ibverbs-utils libibverbs-dev libibumad3 libibumad-dev librdmacm-dev rdmacm-utils infiniband-diags \
    && rm -rf /var/lib/apt/lists/*

# --- Build and Install GDRCopy from Source ---
# This must be done BEFORE UCX so UCX can be configured with GDRCopy support.
# Note: The GDRCopy kernel module (gdrdrv.ko) should ideally be installed and loaded on the HOST system.
# This section builds and installs user-space libraries and tools to ${GDRCOPY_HOME} (i.e. /usr/local).
RUN cd /tmp && \
    git clone https://github.com/NVIDIA/gdrcopy.git && \
    cd gdrcopy && \
    git checkout tags/v${GDRCOPY_VERSION} && \
    # Use Makefile targets to install libs, headers, and executables to ${GDRCOPY_HOME}
    # Since GDRCOPY_HOME is /usr/local, this installs to standard system locations.
    make \
        prefix=${GDRCOPY_HOME} \
        lib_install exes_install && \
    # Update the dynamic linker cache so it finds the newly installed libraries in /usr/local/lib
    ldconfig && \
    cd / && \
    rm -rf /tmp/gdrcopy

# Add GDRCopy paths to environment variables for consistency and explicitness.
# /usr/local/bin should already be in PATH and /usr/local/lib in linker paths on many systems,
# but explicitly setting them ensures they are available.
ENV PATH=${GDRCOPY_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${GDRCOPY_HOME}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${GDRCOPY_HOME}/include:${CPATH}
ENV LIBRARY_PATH=${GDRCOPY_HOME}/lib:${LIBRARY_PATH}
# If GDRCopy installs a .pc file to ${GDRCOPY_HOME}/lib/pkgconfig:
# ENV PKG_CONFIG_PATH=${GDRCOPY_HOME}/lib/pkgconfig:${PKG_CONFIG_PATH}

# --- Build and Install UCX from Source ---
RUN cd /tmp && \
    wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz && \
    tar -zxf ucx-${UCX_VERSION}.tar.gz && \
    cd ucx-${UCX_VERSION} && \
    # Configure UCX for release, with InfiniBand (verbs), RDMACM, CUDA, and optimizations.
    ./contrib/configure-release            \
        --prefix=${UCX_HOME}               \
        --with-cuda=${CUDA_HOME}           \
        --with-gdrcopy=${GDRCOPY_HOME}     \
        --enable-shared                    \
        --disable-static                   \
        --disable-doxygen-doc              \
        --enable-optimizations             \
        --enable-cma                       \
        --enable-devel-headers             \
        --with-verbs                       \
        --with-mlx5-dv                     \
        --with-dm                          \
        --enable-mt                        \
    && make -j$(nproc) && \
    make install-strip && \
    cd / && \
    rm -rf /tmp/ucx-${UCX_VERSION} /tmp/ucx-${UCX_VERSION}.tar.gz


# Add UCX paths to environment variables
ENV PATH=${UCX_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${UCX_HOME}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${UCX_HOME}/include:${CPATH}
ENV LIBRARY_PATH=${UCX_HOME}/lib:${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${UCX_HOME}/lib/pkgconfig:${PKG_CONFIG_PATH}

# --- Build and Install NIXL from Source ---
RUN mkdir -p ${NIXL_SOURCE_DIR} && cd ${NIXL_SOURCE_DIR} && \
    wget "https://github.com/ai-dynamo/nixl/archive/refs/tags/${NIXL_VERSION}.tar.gz" \
        -O "nixl-${NIXL_VERSION}.tar.gz" && \
    tar --strip-components=1 -zxvf "nixl-${NIXL_VERSION}.tar.gz" && \
    rm "nixl-${NIXL_VERSION}.tar.gz" && \
    mkdir build && \
    meson setup build/      \
        --prefix=${NIXL_PREFIX} \
        -Dbuildtype=release &&  \
    cd build && \
    ninja && \
    ninja install
# NOTE(tms): We keep around both nixl source and build for pip installing during
# the vllm-source-installer initContainer.
    
# Set NIXL environment variables
ENV LD_LIBRARY_PATH=${NIXL_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
ENV NIXL_PLUGIN_DIR=${NIXL_PREFIX}/lib/x86_64-linux-gnu/plugins

# Copy project files
COPY Justfile.remote ./Justfile
COPY requirements.txt .

# Install UV
RUN curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR="/usr/local/bin/" sh
RUN which uv

WORKDIR ${HOME}
COPY init-tms.sh .
RUN cd $HOME && bash /app/init-tms.sh

# For neovim.appimage
RUN echo "export APPIMAGE_EXTRACT_AND_RUN=1" >> $HOME/.zshrc

WORKDIR /app/vllm
ENTRYPOINT ["/app/vllm/.venv/bin/python", "-m", "vllm.entrypoints.openai.api_server"]

