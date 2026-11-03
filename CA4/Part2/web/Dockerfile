# Build multi-stage: a imagem final so tem o JRE e o JAR.
FROM eclipse-temurin:21-jdk AS build
WORKDIR /src
COPY app/ ./
RUN chmod +x gradlew && ./gradlew --no-daemon bootJar -x test

FROM eclipse-temurin:21-jre-alpine
RUN apk add --no-cache wget \
 && addgroup -S bookstore && adduser -S -G bookstore bookstore
WORKDIR /app
COPY --from=build /src/build/libs/*.jar app.jar
USER bookstore
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
