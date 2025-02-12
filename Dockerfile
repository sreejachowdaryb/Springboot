FROM redhat.registry.td.com/ubi8/ubi-minimal:8.10

ARG JAVA_VERSION=17
ARG MAVEN_VERSION=3.9.4
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3033
RUN echo "Register with TD Satellite" && \
        curl -sS --insecure https://crrhsaaprzzr20.prd.vmc2.td.com/pub/scripts/container_ubi.sh | /bin/bash && \
    echo "Install OS packages" && \
        microdnf update -y && \
        microdnf upgrade -y && \
        microdnf install -y "java-${JAVA_VERSION}-openjdk-devel" git unzip && \
    echo "Install Maven" && \
        curl --output /tmp/apache-maven.zip "https://repo.td.com/repository/maven-central/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.zip" && \
        unzip -C -d /usr/share /tmp/apache-maven.zip && \
        ln -s "/usr/share/apache-maven-${MAVEN_VERSION}/bin/mvn" /usr/local/bin/mvn && \
        mkdir --parents "$HOME/.m2/" && \
        curl --output "$HOME/.m2/settings.xml" https://nexus.tds.td.com/repository/tools/swe/edp-settings.xml && \
    echo "Adding User" && \
        microdnf install shadow-utils && \
        useradd user && \
    echo "Cleanup OS packages" && \
        microdnf clean all && \
        rm -rf /var/cache/dnf* && \
        rm -rf /usr/share/doc* && \
        rm -rf /etc/pki/entitlement/custom-key.pem

WORKDIR /app

# Build and install project dependencies
COPY pom.xml pom.xml
COPY gsi-fraud-detection-api/pom.xml gsi-fraud-detection-api/pom.xml
COPY gsi-fraud-detection-app/pom.xml gsi-fraud-detection-app/pom.xml
COPY gsi-fraud-detection-config/pom.xml gsi-fraud-detection-config/pom.xml
COPY gsi-fraud-detection-impl/pom.xml gsi-fraud-detection-impl/pom.xml
COPY gsi-fraud-detection-ldap/pom.xml gsi-fraud-detection-ldap/pom.xml

ENV MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
RUN mvn --threads 1C dependency:go-offline dependency:resolve dependency:resolve-plugins || echo 'Skipping build failure'

# Build the app
COPY gsi-fraud-detection-api gsi-fraud-detection-api
COPY gsi-fraud-detection-app gsi-fraud-detection-app
COPY gsi-fraud-detection-config gsi-fraud-detection-config
COPY gsi-fraud-detection-impl gsi-fraud-detection-impl
COPY gsi-fraud-detection-ldap gsi-fraud-detection-ldap
RUN mvn --threads 1C package spring-boot:repackage -Dmaven.test.skip=true -DuniqueVersion=false

USER user

CMD ["java", "-jar", "gsi-fraud-detection-app/target/gsi-fraud-detection-app.jar"]
HEALTHCHECK --interval=60s --timeout=1s --start-period=1s --retries=3 CMD [ "curl", "http://localhost:8443/gsifrauddetection/actuator/health" ]
