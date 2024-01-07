# Build stage
FROM debian:bullseye-slim as builder
ARG MANGOS_DATABASE_VERSION=master

RUN apt-get update && \
    apt-get install -y git wget && \
    git clone https://github.com/mangostwo/database.git -b ${MANGOS_DATABASE_VERSION} --recursive && \
    git clone https://github.com/mangos/Realm_DB.git -b ${MANGOS_DATABASE_VERSION} --recursive && \
    wget --no-check-certificate https://raw.githubusercontent.com/berodin/mangos-docker/test/launch_mysql.sh && \
    chmod a+x launch_mysql.sh && \
    rm -rf /var/lib/apt/lists/*

# Run stage
FROM mysql:8.2.0

# Copy artifacts from the build stage
COPY --from=builder /database /database
COPY --from=builder /Realm_DB /Realm_DB
COPY --from=builder /launch_mysql.sh /launch_mysql.sh

EXPOSE 3306

ENTRYPOINT ["./launch_mysql.sh"]
CMD ["mysqld"]
