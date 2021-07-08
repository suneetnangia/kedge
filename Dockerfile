FROM ubuntu:18.04
RUN apt-get update && \
    apt install -y systemd && \
    apt-get install -y curl && \
    apt-get install -y gpg && \
    curl https://packages.microsoft.com/config/ubuntu/18.04/multiarch/prod.list > ./microsoft-prod.list && \
    cp ./microsoft-prod.list /etc/apt/sources.list.d/ && \
    curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg  && \
    cp ./microsoft.gpg /etc/apt/trusted.gpg.d/ && \
    apt-get update  && \
    apt-get install -y moby-engine && \
    apt-get update && \
    apt-get install -y aziot-edge
COPY ./config.toml /etc/aziot/config.toml
RUN iotedge config apply
STOPSIGNAL SIGRTMIN+3
CMD [ "/sbin/init" ]