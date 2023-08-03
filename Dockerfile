FROM openjdk:17-oracle AS builder
RUN microdnf install findutils
COPY gradlew .
COPY settings.gradle .
COPY build.gradle .
COPY gradle gradle
COPY src src
COPY backend-config backend-config
RUN chmod +x ./gradlew
RUN ls -la
RUN ./gradlew build

FROM openjdk:17-oracle
RUN mkdir /opt/app
COPY --from=builder build/libs/*.jar /opt/app/spring-boot-application.jar
EXPOSE 8080
ENV	PROFILE local
ENTRYPOINT ["java", "-jar", "-Dspring.profiles.active=${PROFILE}" ,"/opt/app/spring-boot-application.jar"]