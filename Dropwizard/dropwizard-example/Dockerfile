FROM maven:3.5.0-jdk-8

MAINTAINER Ivan Suftin <isuftin@usgs.gov>

COPY root.crt /usr/lib/ssl/certs/local.crt
RUN	ln -sf /usr/lib/ssl/certs/local.crt /usr/lib/ssl/certs/`openssl x509 -hash -noout -in /usr/lib/ssl/certs/local.crt`.0
RUN	/usr/bin/keytool -keystore $JAVA_HOME/jre/lib/security/cacerts -importcert -alias DOIRootCA.crt -file /usr/lib/ssl/certs/local.crt -storepass changeit -noprompt

COPY ./Source /Source

WORKDIR /Source

RUN mvn package

COPY ./db-migrate.yml /db-migrate.yml

RUN java -jar /Source/target/dropwizard-example-1.2.0-SNAPSHOT.jar db migrate /db-migrate.yml

CMD java -jar /Source/target/dropwizard-example-1.2.0-SNAPSHOT.jar server /configs/dropwizard-example.yml

HEALTHCHECK --interval=30s --timeout=2s \
 CMD curl --fail 'http://localhost:8081/healthcheck' || exit 1
