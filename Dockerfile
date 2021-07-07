FROM jrei/systemd-ubuntu
RUN apt-get update
RUN apt-get install -y curl
RUN apt-get install -y gpg
RUN curl https://packages.microsoft.com/config/ubuntu/18.04/multiarch/prod.list > ./microsoft-prod.list
RUN cp ./microsoft-prod.list /etc/apt/sources.list.d/
RUN curl https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg
RUN cp ./microsoft.gpg /etc/apt/trusted.gpg.d/
RUN apt-get update
RUN apt-get install -y moby-engine
RUN apt-get update
RUN apt-get install -y aziot-edge
# TODO: Copy hardcoded config file for now, change this to allow external device config.
COPY ./config.toml /etc/aziot/config.toml
RUN iotedge config apply