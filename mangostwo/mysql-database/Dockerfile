# Build stage
FROM debian:bullseye-slim as builder

ARG MANGOS_DATABASE_VERSION=master
RUN apt-get update && \
    apt-get install -y git wget && \
    git clone https://github.com/mangostwo/database.git -b ${MANGOS_DATABASE_VERSION} --recursive && \
    wget --no-check-certificate https://raw.githubusercontent.com/berodin/mangos-docker/master/launch_mysql.sh && \
    chmod a+x launch_mysql.sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/*

# Run stage
FROM mysql:8.0.35

# Set environment variables
ENV MANGOS_DATABASE_REALM_NAME=Karazhan \
    MANGOS_SERVER_VERSION=2 \
    MANGOS_DB_RELEASE=Rel21 \
    MYSQL_USER=mangos \
    MYSQL_PASSWORD=mangos

# Copy artifacts from the build stage
COPY --from=builder /database /database
COPY --from=builder /launch_mysql.sh /launch_mysql.sh

EXPOSE 3306

ENTRYPOINT ["./launch_mysql.sh"]
CMD ["mysqld"]
