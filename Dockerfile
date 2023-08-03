FROM adoptopenjdk:11 AS builder
COPY .editorconfig .
COPY gradlew .
COPY settings.gradle.kts .
COPY build.gradle.kts .
COPY gradle gradle
COPY src src
COPY backend-config backend-config
RUN chmod +x ./gradlew
RUN ./gradlew build

FROM adoptopenjdk:11
RUN mkdir /opt/app
COPY --from=builder build/libs/*.jar /opt/app/spring-boot-application.jar
EXPOSE 8080
ENV	PROFILE local
ENTRYPOINT ["java", "-jar", "-Dspring.profiles.active=${PROFILE}" ,"/opt/app/spring-boot-application.jar"]