FROM debian:11

# Non-interactive mode
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    debhelper \
    devscripts \
    fakeroot \
    quilt \
    bison \
    flex \
    perl \
    libreadline-dev \
    zlib1g-dev \
    libssl-dev \
    libpam0g-dev \
    libxml2-dev \
    libldap2-dev \
    libossp-uuid-dev \
    uuid-dev \
    libcurl4-openssl-dev \
    liblz4-dev \
    libzstd-dev \
    libssh2-1-dev \
    libatomic1 \
    pkg-config \
    libtool \
    && (apt-get install -y libpqxx-dev || true) \
    && (apt-get install -y libcli11-dev || true) \
    && (apt-get install -y curl cmake || true) \
    # CLI11 single-header fallback (libcli11-dev not available on Debian 11)
    && (test -f /usr/include/CLI/CLI.hpp || \
        (mkdir -p /usr/include/CLI && \
         curl -fsSL https://github.com/CLIUtils/CLI11/releases/download/v2.4.2/CLI11.hpp -o /usr/include/CLI/CLI.hpp)) \
    # libpqxx 7.9.2 source build (libpqxx-dev not available or incompatible on older distros)
    && (test -f /usr/include/pqxx/pqxx || \
        (cd /tmp && \
         curl -fsSL https://github.com/jtv/libpqxx/archive/refs/tags/7.9.2.tar.gz -o libpqxx.tar.gz && \
         tar xzf libpqxx.tar.gz && \
         cd libpqxx-7.9.2 && \
         cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_SHARED_LIBS=ON -DSKIP_BUILD_TEST=ON && \
         cmake --build build -j$(nproc) && \
         cmake --install build && \
         cd /tmp && rm -rf libpqxx* && ldconfig)) \
    && rm -rf /var/lib/apt/lists/*

# Ensure libatomic.so symlink exists for linking
RUN if [ ! -f /usr/lib/x86_64-linux-gnu/libatomic.so ] && [ -f /usr/lib/x86_64-linux-gnu/libatomic.so.1 ]; then \
        ln -sf /usr/lib/x86_64-linux-gnu/libatomic.so.1 /usr/lib/x86_64-linux-gnu/libatomic.so; \
    fi

# Work directory
WORKDIR /build

# Copy build script
COPY packaging/scripts/build-deb.sh /build/
RUN chmod +x /build/build-deb.sh

# Default: run build
CMD ["/build/build-deb.sh"]
