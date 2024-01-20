# Build stage
FROM debian:bullseye-slim as builder
ARG MANGOS_DATABASE_VERSION=master

RUN apt-get update && \
    apt-get install -y git wget && \
    git clone https://github.com/mangosone/database.git -b ${MANGOS_DATABASE_VERSION} --recursive && \
    git clone https://github.com/mangos/Realm_DB.git /Realm_DB && \
    cd /Realm_DB && \
    git checkout 08fe8f75a5751db811a0f5e7a191e1b74c4226ea && \
    cd .. && \
    wget --no-check-certificate https://raw.githubusercontent.com/berodin/mangos-docker/test/launch_mysql.sh && \
    chmod a+x launch_mysql.sh && \
    rm -rf /var/lib/apt/lists/*

# Run stage
FROM mariadb:10.4

# Copy artifacts from the build stage
COPY --from=builder /database /database
COPY --from=builder /Realm_DB /Realm_DB
COPY --from=builder /launch_mysql.sh /launch_mysql.sh

EXPOSE 3306

ENTRYPOINT ["./launch_mysql.sh"]
CMD ["mysqld"]
