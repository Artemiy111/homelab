FROM eclipse-temurin:21-alpine AS clone
RUN apk add --no-cache git \
    && git clone --depth 1 --branch v2026.06.28 https://github.com/structurizr/structurizr.git /src

FROM maven:3.9-eclipse-temurin-21 AS build
COPY --from=clone /src /src
WORKDIR /src
RUN ./mvnw -q -Dmaven.test.skip=true -Dapp.revision=2026.06.28 package

FROM eclipse-temurin:21-alpine AS runtime
ENV PORT=8080
COPY --from=build /src/structurizr-application/target/structurizr-2026.06.28.war /usr/local/structurizr.war
COPY --from=build /src/structurizr-themes /usr/local/structurizr-themes
WORKDIR /usr/local/structurizr
ENTRYPOINT ["/bin/sh", "-c", "exec java -Dserver.port=${PORT} -Dio.netty.noUnsafe=true --enable-native-access=ALL-UNNAMED -jar /usr/local/structurizr.war server"]
