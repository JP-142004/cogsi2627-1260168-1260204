FROM eclipse-temurin:21-jre-alpine

# H2 em modo servidor TCP. Versao fixa para builds reproduziveis.
ARG H2_VERSION=2.2.224
RUN apk add --no-cache netcat-openbsd \
 && wget -qO /opt/h2.jar https://repo1.maven.org/maven2/com/h2database/h2/${H2_VERSION}/h2-${H2_VERSION}.jar \
 && addgroup -S h2 && adduser -S -G h2 h2 \
 && mkdir -p /data && chown h2:h2 /data

ENV H2_PORT=9092 H2_BASE_DIR=/data

USER h2
VOLUME ["/data"]
EXPOSE 9092

ENTRYPOINT ["sh", "-c", "exec java -cp /opt/h2.jar org.h2.tools.Server -tcp -tcpPort ${H2_PORT} -tcpAllowOthers -ifNotExists -baseDir ${H2_BASE_DIR}"]