FROM gcc:12.3.0 as builder
ARG MANGOS_SERVER_VERSION=master
ARG THREAD_COUNT="-j7"
ARG CMAKE_VERSION="3.22.1"
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
WORKDIR /var/etc/mangos/

# Installieren Sie benötigte Abhängigkeiten und fügen Sie das GCC 12 Repository hinzu
RUN apt-get update && \
    apt-get install -y software-properties-common && \
    add-apt-repository ppa:ubuntu-toolchain-r/test && \
    apt-get update && \
    apt-get install -y gcc-12 g++-12 libstdc++6 libmariadb-dev libmariadb-dev-compat libmariadbd19 libmariadb3 libssl-dev wget

# Setzen Sie GCC 12 als Standardcompiler
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-12 60 --slave /usr/bin/g++ g++ /usr/bin/g++-12

# Kopieren Sie die kompilierten Binärdateien und Konfigurationsdateien vom Builder
COPY --from=builder /server/install/bin ./bin
COPY --from=builder /server/install/etc ./conf

# Weitere Setup-Schritte
RUN useradd -ms /bin/bash mangos && \
    wget --no-check-certificate https://raw.githubusercontent.com/Berodin/mangos-docker/test/launch_mangosd.sh && \
    chmod -R a+x . && \
    mv conf/mangosd.conf.dist conf/mangosd.conf && \
    chown -R mangos:mangos . && \
    rm -rf /var/lib/apt/lists/*

USER mangos
ENTRYPOINT ["./launch_mangosd.sh"]

