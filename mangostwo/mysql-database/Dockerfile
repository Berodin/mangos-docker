# Build stage
FROM debian:bullseye-slim as builder

# Install dependencies
RUN apt-get update && \
    apt-get install -y git wget && \
    rm -rf /var/lib/apt/lists/*

# Clone the repository
ARG MANGOS_DATABASE_VERSION=master
RUN git clone https://github.com/mangostwo/database.git -b ${MANGOS_DATABASE_VERSION} --recursive

# Download the launch script
RUN wget --no-check-certificate https://raw.githubusercontent.com/berodin/mangos-docker/test/launch_mysql.sh && \
    chmod a+x launch_mysql.sh

# Run stage
FROM mysql:8.0.35

# Set environment variables
ENV MANGOS_DATABASE_REALM_NAME=Karazhan \
    MANGOS_SERVER_VERSION=2 \
    MANGOS_DB_RELEASE=Rel21 \
    MYSQL_USER=mangos \
    MYSQL_PASSWORD=mangos \
    MYSQL_ROOT_HOST=%


# Copy artifacts from the build stage
COPY --from=builder /database /database
COPY --from=builder /launch_mysql.sh /launch_mysql.sh

EXPOSE 3306

ENTRYPOINT ["./launch_mysql.sh"]
CMD ["mysqld"]
