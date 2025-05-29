# Dockerfile for vLLM development
# Use a CUDA base image.
FROM docker.io/nvidia/cuda:12.8.1-devel-ubuntu24.04

WORKDIR /app

# NOTE: currently only used for building NVSHMEM
ARG MAX_JOBS=16
ENV MAX_JOBS=${MAX_JOBS}

ENV PYTHON_VERSION=3.12
ENV UCX_VERSION=1.18.1
ENV UCX_HOME=/opt/ucx
ENV CUDA_HOME=/usr/local/cuda/
ENV GDRCOPY_VERSION=2.5
ENV GDRCOPY_HOME=/usr/local
ENV NIXL_VERSION="0.2.1"
ENV NIXL_SOURCE_DIR=/opt/nixl
ENV NIXL_PREFIX=/usr/local/nixl
ENV NVSHMEM_VERSION=3.2.5-1
ENV NVSHMEM_PREFIX=/opt/nvshmem-${NVSHMEM_VERSION}

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
    # Build tools for UCX, NVSHMEM, etc.
    build-essential \
    autoconf automake libtool pkg-config \
    meson ninja-build cmake \
    # Other dependencies
    libnuma-dev \
    # RDMA stack (Mellanox OFED)
    ibverbs-utils libibverbs-dev libibumad3 libibumad-dev \
    librdmacm-dev rdmacm-utils infiniband-diags \
    # MPI / PMIx / libfabric for NVSHMEM
    libopenmpi-dev openmpi-bin \
    libpmix-dev libfabric-dev \
    && rm -rf /var/lib/apt/lists/*

# --- Build and Install GDRCopy from Source ---
RUN cd /tmp && \
    git clone https://github.com/NVIDIA/gdrcopy.git && \
    cd gdrcopy && \
    git checkout tags/v${GDRCOPY_VERSION} && \
    make prefix=${GDRCOPY_HOME} lib_install exes_install && \
    ldconfig && \
    rm -rf /tmp/gdrcopy

ENV PATH=${GDRCOPY_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${GDRCOPY_HOME}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${GDRCOPY_HOME}/include:${CPATH}
ENV LIBRARY_PATH=${GDRCOPY_HOME}/lib:${LIBRARY_PATH}

# --- Build and Install UCX from Source ---
RUN cd /tmp && \
    wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz && \
    tar -zxf ucx-${UCX_VERSION}.tar.gz && \
    cd ucx-${UCX_VERSION} && \
    ./contrib/configure-release         \
        --prefix=${UCX_HOME}            \
        --with-cuda=${CUDA_HOME}        \
        --with-gdrcopy=${GDRCOPY_HOME}  \
        --enable-shared         \
        --disable-static        \
        --disable-doxygen-doc   \
        --enable-optimizations  \
        --enable-cma            \ 
        --enable-devel-headers  \
        --with-verbs            \
        --with-dm               \ 
        --enable-mt             \
    && make -j$(nproc) && make install-strip && \
    rm -rf /tmp/ucx-${UCX_VERSION}*

ENV PATH=${UCX_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${UCX_HOME}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${UCX_HOME}/include:${CPATH}
ENV LIBRARY_PATH=${UCX_HOME}/lib:${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${UCX_HOME}/lib/pkgconfig:${PKG_CONFIG_PATH}


# --- Build and Install NIXL from Source ---
RUN cd /tmp \
    && wget "https://github.com/ai-dynamo/nixl/archive/refs/tags/${NIXL_VERSION}.tar.gz" \
        -O "nixl-${NIXL_VERSION}.tar.gz" \
    && mkdir -p ${NIXL_SOURCE_DIR} \
    && tar --strip-components=1 -xzf "nixl-${NIXL_VERSION}.tar.gz" -C ${NIXL_SOURCE_DIR} \
    && rm "nixl-${NIXL_VERSION}.tar.gz" \
    \
    # create an out-of-source build directory
    && mkdir -p ${NIXL_SOURCE_DIR}/build \
    && cd ${NIXL_SOURCE_DIR}/build \
    \
    # configure, compile, install
    && meson setup .. \
         --prefix=${NIXL_PREFIX} \
         -Dbuildtype=release \
    && ninja -C . \
    && ninja -C . install \
    \
    # cleanup
    && rm -rf ${NIXL_SOURCE_DIR}/build

ENV LD_LIBRARY_PATH=${NIXL_PREFIX}/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}
ENV NIXL_PLUGIN_DIR=${NIXL_PREFIX}/lib/x86_64-linux-gnu/plugins

# --- Build and Install NVSHMEM from Source ---
RUN cd /tmp && \
    wget https://developer.nvidia.com/downloads/assets/secure/nvshmem/nvshmem_src_${NVSHMEM_VERSION}.txz && \
    tar -xf nvshmem_src_${NVSHMEM_VERSION}.txz && \
    cd nvshmem_src && \
    mkdir build && cd build && \
    cmake \
      -G Ninja \
      -DNVSHMEM_PREFIX=${NVSHMEM_PREFIX} \
      -DCMAKE_CUDA_ARCHITECTURES="80;89;90a;100a" \
      -DNVSHMEM_MPI_SUPPORT=1            \
      -DNVSHMEM_PMIX_SUPPORT=0           \
      -DNVSHMEM_LIBFABRIC_SUPPORT=1      \
      -DNVSHMEM_IBRC_SUPPORT=1           \
      -DNVSHMEM_IBGDA_SUPPORT=1          \
      -DNVSHMEM_BUILD_TESTS=0            \
      -DNVSHMEM_BUILD_EXAMPLES=0         \
      -DNVSHMEM_USE_GDRCOPY=1            \
      -DMPI_HOME=/usr                    \
      -DLIBFABRIC_HOME=/usr              \
      -DGDRCOPY_HOME=${GDRCOPY_HOME}     \
      .. && \
    ninja -j${MAX_JOBS} && \
    ninja -j${MAX_JOBS} install && \
    rm -rf /tmp/nvshmem_src_${NVSHMEM_VERSION}*

ENV PATH=${NVSHMEM_PREFIX}/bin:${PATH}
ENV LD_LIBRARY_PATH=${NVSHMEM_PREFIX}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${NVSHMEM_PREFIX}/include:${CPATH}
ENV LIBRARY_PATH=${NVSHMEM_PREFIX}/lib:${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${NVSHMEM_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}

# Install UV
RUN curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR="/usr/local/bin/" sh

# Install my dotfiles
WORKDIR ${HOME}
RUN echo "Cloning and installing dotfiles"
RUN git clone https://github.com/tlrmchlsmth/dotfiles.git
RUN cd dotfiles && bash install.sh

# For neovim.appimage
RUN echo "export APPIMAGE_EXTRACT_AND_RUN=1" >> $HOME/.zshrc

WORKDIR /app/vllm
ENTRYPOINT ["/app/code/venv/bin/vllm", "serve"]
