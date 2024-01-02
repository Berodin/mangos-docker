FROM gcc:latest as builder
ARG MANGOS_SERVER_VERSION=master
ARG THREAD_COUNT="-j4"
ARG CMAKE_VERSION="3.28.1"
ENV GIT_HTTP_LOW_SPEED_LIMIT 0
ENV GIT_HTTP_TRANSFER_TIMEOUT 1200

RUN git config --global http.postBuffer 524288000
RUN git config --global core.compression 0
RUN git config --global http.lowSpeedLimit 0
RUN git config --global http.lowSpeedTime 999999

RUN apt-get update -qq && \
    apt-get install -y openssl libssl-dev && \
    wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-aarch64.sh && \
    chmod +x cmake-${CMAKE_VERSION}-linux-aarch64.sh && \
    ./cmake-${CMAKE_VERSION}-linux-aarch64.sh --skip-license --prefix=/usr/local

RUN git clone https://github.com/mangostwo/server.git -b ${MANGOS_SERVER_VERSION} /server || \
    (echo "Retrying git clone..." && sleep 30 && git clone https://github.com/mangostwo/server.git -b ${MANGOS_SERVER_VERSION} /server)
RUN cd /server && \
    git submodule update --init --recursive || \
    (echo "Retrying git submodule update..." && sleep 30 && git submodule update --init --recursive)

# Build the project
RUN cd server && \
    cmake . -DBUILD_REALMD=No -DBUILD_TOOLS=No -DCONF_INSTALL_DIR=/server/install/etc/ && \
    make ${THREAD_COUNT} && \
    make install ${THREAD_COUNT}

FROM ubuntu:22.04
EXPOSE 3724
ENV LOGIN_DATABASE_INFO=127.0.0.1;3306;root;mangos;realmd
WORKDIR /etc/mangos/
COPY --from=builder /server/install/bin ./bin
COPY --from=builder /server/install/etc ./conf
RUN apt-get update && \
    apt-get install wget libstdc++6 libmariadb-dev libmariadb-dev-compat libmariadbd19 libmariadb3 libssl-dev -y && \
    useradd -ms /bin/bash mangos && \
    wget --no-check-certificate https://raw.githubusercontent.com/Berodin/mangos-docker/master/launch_mangosd.sh && \
    chmod -R a+x . && \
    mv conf/mangosd.conf.dist conf/mangosd.conf && \
    sed -i 's|^LoginDatabaseInfo            =.*$|LoginDatabaseInfo            = LOGIN_DATABASE_INFO|' conf/mangosd.conf && \
    sed -i 's|^WorldDatabaseInfo            =.*$|WorldDatabaseInfo            = WORLD_DATABASE_INFO|' conf/mangosd.conf && \
    sed -i 's|^CharacterDatabaseInfo        =.*$|CharacterDatabaseInfo        = CHARACTER_DATABASE_INFO|' conf/mangosd.conf && \
    sed -i 's|/server/install/etc/|/etc/mangos/|' conf/mangosd.conf && \
    chown -R mangos:mangos . && \
    rm -rf /var/lib/apt/lists/*
USER mangos
CMD ["./launch_mangosd.sh"]