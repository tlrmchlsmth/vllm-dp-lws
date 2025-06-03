# Dockerfile for vLLM development
# Use a CUDA base image.
FROM docker.io/nvidia/cuda:12.8.1-devel-ubuntu22.04 as base

WORKDIR /app

# NOTE: Currently not used for building UCX, GDRCOPY or NIXL
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

ENV DEBIAN_FRONTEND=noninteractive

RUN echo 'tzdata tzdata/Areas select America' | debconf-set-selections \
    && echo 'tzdata tzdata/Zones/America select New_York' | debconf-set-selections \
    && apt-get -qq update \
    && apt-get -qq install -y ccache software-properties-common git wget curl \
    && for i in 1 2 3; do \
        add-apt-repository -y ppa:deadsnakes/ppa && break || \
        { echo "Attempt $i failed, retrying in 5s..."; sleep 5; }; \
    done \
    && apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
      # Python and related tools
      python${PYTHON_VERSION} \
      python${PYTHON_VERSION}-dev \
      python${PYTHON_VERSION}-venv \
      ca-certificates \
      htop \
      iputils-ping net-tools \
      vim ripgrep bat clangd fuse fzf \
      nodejs npm clang fd-find xclip \
      zsh \
      # Build tools for UCX, NVSHMEM, etc.
      build-essential \
      autoconf automake libtool pkg-config \
      ninja-build cmake \
      # Other dependencies
      libnuma1 libsubunit0 libpci-dev \
      # MPI / PMIx / libfabric for NVSHMEM
      libopenmpi-dev openmpi-bin \
      libpmix-dev libfabric-dev \
      datacenter-gpu-manager \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python${PYTHON_VERSION} 1
RUN python${PYTHON_VERSION} -m ensurepip --upgrade
RUN python${PYTHON_VERSION} -m pip install --upgrade pip setuptools wheel

# Mellanox OFED
RUN wget -qO - https://www.mellanox.com/downloads/ofed/RPM-GPG-KEY-Mellanox | apt-key add -
RUN cd /etc/apt/sources.list.d/ && wget https://linux.mellanox.com/public/repo/mlnx_ofed/24.10-0.7.0.0/ubuntu22.04/mellanox_mlnx_ofed.list

RUN apt-get -qq update \
    && apt-get -qq install -y --no-install-recommends \
      ibverbs-utils libibverbs-dev libibumad3 libibumad-dev librdmacm-dev rdmacm-utils infiniband-diags ibverbs-utils \
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
RUN cd /tmp \
    && wget https://github.com/openucx/ucx/releases/download/v${UCX_VERSION}/ucx-${UCX_VERSION}.tar.gz \
    && tar -zxf ucx-${UCX_VERSION}.tar.gz \
    && cd ucx-${UCX_VERSION} \
    && ./contrib/configure-release      \
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
    && make -j$(nproc) && make install-strip \
    && rm -rf /tmp/ucx-${UCX_VERSION}*

ENV PATH=${UCX_HOME}/bin:${PATH}
ENV LD_LIBRARY_PATH=${UCX_HOME}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${UCX_HOME}/include:${CPATH}
ENV LIBRARY_PATH=${UCX_HOME}/lib:${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${UCX_HOME}/lib/pkgconfig:${PKG_CONFIG_PATH}


# --- Build and Install NIXL from Source ---

# Grab meson from pip, since the 22.04 version of meson is not new enough.
RUN python${PYTHON_VERSION} -m pip install 'meson>=0.64.0' pybind11

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

ENV MPI_HOME=/usr/lib/x86_64-linux-gnu/openmpi
ENV CPATH=${MPI_HOME}/include:${CPATH}

RUN export CC=/usr/bin/mpicc CXX=/usr/bin/mpicxx && \
    cd /tmp \
    && wget https://developer.nvidia.com/downloads/assets/secure/nvshmem/nvshmem_src_${NVSHMEM_VERSION}.txz \
    && tar -xf nvshmem_src_${NVSHMEM_VERSION}.txz \
    && cd nvshmem_src \
    && mkdir build \
    && cd build \
    && cmake \
      -G Ninja \
      -DNVSHMEM_PREFIX=${NVSHMEM_PREFIX} \
      -DCMAKE_CUDA_ARCHITECTURES="80;89;90a;100a" \
      -DNVSHMEM_PMIX_SUPPORT=0           \
      -DNVSHMEM_LIBFABRIC_SUPPORT=1      \
      -DNVSHMEM_IBRC_SUPPORT=1           \
      -DNVSHMEM_IBGDA_SUPPORT=1          \
      -DNVSHMEM_IBDEVX_SUPPORT=1         \
      -DNVSHMEM_USE_GDRCOPY=1            \
      -DNVSHMEM_BUILD_TESTS=1            \
      -DNVSHMEM_BUILD_EXAMPLES=0         \
      -DLIBFABRIC_HOME=/usr              \
      -DGDRCOPY_HOME=${GDRCOPY_HOME}     \
      -DNVSHMEM_MPI_SUPPORT=1            \
      .. \
    && ninja -j${MAX_JOBS} \
    && ninja -j${MAX_JOBS} install \
    && rm -rf /tmp/nvshmem_src_${NVSHMEM_VERSION}*

ENV PATH=${NVSHMEM_PREFIX}/bin:${PATH}
ENV LD_LIBRARY_PATH=${NVSHMEM_PREFIX}/lib:${LD_LIBRARY_PATH}
ENV CPATH=${NVSHMEM_PREFIX}/include:${CPATH}
ENV LIBRARY_PATH=${NVSHMEM_PREFIX}/lib:${LIBRARY_PATH}
ENV PKG_CONFIG_PATH=${NVSHMEM_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}

# Install UV
RUN curl -LsSf https://astral.sh/uv/install.sh \
        | env UV_INSTALL_DIR="/usr/local/bin/" sh

# For neovim.appimage
RUN echo "export APPIMAGE_EXTRACT_AND_RUN=1" >> $HOME/.zshrc

# Squash a warning
RUN rm /etc/libibverbs.d/vmw_pvrdma.driver

# Install dependencies - NIXL (python), PPLX-A2A, DeepEP
COPY install-deps.sh /tmp/
RUN chmod +x /tmp/install-deps.sh \
    && /tmp/install-deps.sh \
    && rm /tmp/install-deps.sh

ENTRYPOINT ["/app/code/venv/bin/vllm", "serve"]

#==============================================================================

FROM base AS varun-deepep

# Install dependencies - NIXL (python), PPLX-A2A, DeepEP
COPY init-vllm.sh /tmp/
RUN chmod +x /tmp/init-vllm.sh \
    && VLLM_REPO_URL="https://github.com/neuralmagic/vllm.git" \
       VLLM_BRANCH="varun/deepep" \
       /tmp/init-vllm.sh \
       rm /tmp/init-vllm.sh

ENTRYPOINT ["/app/code/venv/bin/vllm", "serve"]
