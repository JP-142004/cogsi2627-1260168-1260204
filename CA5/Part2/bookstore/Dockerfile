FROM eclipse-temurin:17-jre-jammy

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 bookstore \
    && useradd --system --uid 10001 --gid bookstore --home-dir /app --no-create-home bookstore

WORKDIR /app

# O stage Assemble produz o bootJar; o JAR plain nunca entra na imagem.
COPY --chown=10001:10001 app/build/libs/app-1.0.0.jar /app/bookstore.jar

USER 10001:10001
EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=5s --start-period=90s --retries=12 \
    CMD curl --fail --silent --show-error --max-time 4 http://127.0.0.1:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "/app/bookstore.jar"]
