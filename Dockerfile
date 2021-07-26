# Dockerfile to build Azure IoT Edge >v1.2 container based on Ubuntu
FROM ubuntu:18.04

# Deploys all required binaries and dependencies for Azure IoT Edge runtime.
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

# Create a systemd service to apply edge device config when container starts.
COPY ./aziot-init.service /etc/systemd/system/.
RUN systemctl enable aziot-init.service

STOPSIGNAL SIGRTMIN+3

# Non root user does not load PID1 which is systemd in this case hence commented for now.
# USER 1000
VOLUME /var/lib/docker

# Start systemd service as PID1
ENTRYPOINT ["/sbin/init"]