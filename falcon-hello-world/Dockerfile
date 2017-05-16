FROM ubuntu:16.04
MAINTAINER Andrew Yan "ayan@usgs.gov"
RUN apt update -y
RUN apt install -y python3-pip python3-dev build-essential
RUN mkdir /local
COPY root.crt /tmp/DOIRootCA.crt
RUN openssl x509 -in /tmp/DOIRootCA.crt -out /local/DOIRootCA.pem -outform PEM
RUN mv /tmp/DOIRootCA.crt /usr/local/share/ca-certificates/DOIRootCA.crt
RUN update-ca-certificates
COPY gunicorn_config.py /local/gunicorn_config.py
COPY pip.conf /etc/pip.conf
RUN export PIP_CERT="/etc/ssl/certs/ca-certificates.crt" && \
    pip3 install --upgrade pip && \
    pip3 install falcon-hello-world -i https://pypi.python.org/simple --extra-index-url https://cida.usgs.gov/artifactory/api/pypi/usgs-python-releases/simple -v
ENV bind_ip 0.0.0.0
ENV bind_port 7010
EXPOSE ${bind_port}
CMD ["/usr/local/bin/gunicorn", "--reload",  "greetings.app", "--config", "file:/local/gunicorn_config.py"]
