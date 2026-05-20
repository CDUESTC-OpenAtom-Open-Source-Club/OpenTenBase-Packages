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
    libpqxx-dev \
    libcli11-dev \
    pkg-config \
    libtool \
    && rm -rf /var/lib/apt/lists/*

# Work directory
WORKDIR /build

# Copy build script
COPY build-deb.sh /build/
RUN chmod +x /build/build-deb.sh

# Default: run build
CMD ["/build/build-deb.sh"]
