FROM arm64v8/ubuntu:22.04 as builder
ARG MANGOS_SERVER_VERSION=master
ARG THREAD_COUNT="-j6"
ARG CMAKE_VERSION="3.22.1"

RUN apt-get update -qq && \
    apt-get install -y git wget openssl libssl-dev make gcc-12 g++-12 libmysqlclient-dev && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 100 && \
    update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-12 100 && \
    wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-aarch64.sh && \
    chmod +x cmake-${CMAKE_VERSION}-linux-aarch64.sh && \
    ./cmake-${CMAKE_VERSION}-linux-aarch64.sh --skip-license --prefix=/usr/local && \
    git clone https://github.com/mangostwo/server.git -b ${MANGOS_SERVER_VERSION} /server && \
    cd /server && \
    git submodule update --init --recursive && \
    cmake . -DBUILD_MANGOSD=No -DBUILD_TOOLS=No -DCONF_INSTALL_DIR=/server/install/etc/ && \
    make ${THREAD_COUNT} && \
    make install ${THREAD_COUNT} && \
    rm -rf /var/lib/apt/lists/* /server/.git

FROM arm64v8/ubuntu:22.04
EXPOSE 3724
WORKDIR /etc/mangos/

# Only install necessary packages
RUN apt-get update && \
    apt-get install -y libmariadb-dev libmariadb3 libssl-dev wget libmysqlclient21 && \
    rm -rf /var/lib/apt/lists/*

# Copy necessary files from builder
COPY --from=builder /usr/lib/aarch64-linux-gnu/libstdc++.so.6 /usr/lib/aarch64-linux-gnu/
COPY --from=builder /server/install/bin ./bin
COPY --from=builder /server/install/etc ./conf

# Set up the runtime environment
RUN useradd -ms /bin/bash realm && \
    wget https://raw.githubusercontent.com/Berodin/mangos-docker/test/launch_realmd.sh && \
    chmod -R a+x . && \
    mv conf/realmd.conf.dist conf/realmd.conf && \
    chown -R realm:realm .

USER realm
CMD ["./launch_realmd.sh"]