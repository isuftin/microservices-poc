FROM ubuntu:16.04
MAINTAINER Andrew Yan "ayan@usgs.gov"
RUN apt update -y
RUN apt install -y python3-pip python3-dev build-essential
RUN mkdir /local
ADD http://sslhelp.doi.net/docs/DOIRootCA2.cer /tmp/DOIRootCA.crt
RUN openssl x509 -in /tmp/DOIRootCA.crt -out /local/DOIRootCA.pem -outform PEM
RUN mv /tmp/DOIRootCA.crt /usr/local/share/ca-certificates/DOIRootCA.crt
RUN update-ca-certificates
COPY pip.conf /etc/pip.conf
COPY ./falcon-hello-world /source
RUN export PIP_CERT="/etc/ssl/certs/ca-certificates.crt" && \
    pip3 install --upgrade pip && \
    pip3 install -r /source/requirements.txt -v
EXPOSE 7010
CMD ["/usr/local/bin/gunicorn", "--chdir", "/source", "--reload",  "greetings.app", "--config", "file:/source/gunicorn_config.py"]
