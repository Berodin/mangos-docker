FROM arm64v8/gcc:12.3.0 as builder
ARG MANGOS_SERVER_VERSION=master
ARG THREAD_COUNT="-j6"
ARG CMAKE_VERSION="3.22.1"
ENV GIT_HTTP_LOW_SPEED_LIMIT 0
ENV GIT_HTTP_TRANSFER_TIMEOUT 1200

RUN git config --global http.postBuffer 524288000 && \
    git config --global core.compression 0 && \
    git config --global http.lowSpeedLimit 0 && \
    git config --global http.lowSpeedTime 999999 && \
    apt-get update -qq && \
    apt-get install -y openssl libssl-dev && \
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

FROM arm64v8/gcc:12.3.0
EXPOSE 3724
WORKDIR /etc/mangos/

# Only install necessary packages
RUN apt-get update && \
    apt-get install -y libmariadb-dev libmariadb3 libssl-dev wget && \
    rm -rf /var/lib/apt/lists/*

# Copy necessary files from builder
COPY --from=builder /usr/lib/aarch64-linux-gnu/libstdc++.so.6 /usr/lib/aarch64-linux-gnu/
COPY --from=builder /server/install/bin ./bin
COPY --from=builder /server/install/etc ./conf

# Set up the runtime environment
RUN useradd -ms /bin/bash realm && \
    wget https://raw.githubusercontent.com/Berodin/mangos-docker/master/launch_realmd.sh && \
    chmod -R a+x . && \
    mv conf/realmd.conf.dist conf/realmd.conf && \
    sed -i 's|^LoginDatabaseInfo            =.*$|LoginDatabaseInfo            = LOGIN_DATABASE_INFO|' conf/realmd.conf && \
    chown -R realm:realm .

USER realm
CMD ["./launch_realmd.sh"]