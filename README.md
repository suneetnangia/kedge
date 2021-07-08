# KEdge

Kubernetes based IoT Edge deployment.
This repo demonstrates an experimental deployment of IoT Edge runtime 1.2 on K8s.

![alt text](SimpleK8sEdge.png "Edge on K8s")

## Steps to deploy

1. Authenticate and connect to existing K8s cluster.
2. Update config.toml with your device connection string (currently populated with dummy connection string).
3. Build docker container image (e.g. "docker build -t youracr.azurecr.io/basekedge:preview .").
4. Update kedgedeployment.yaml with your container registery and image uri.
5. Create K8s image pull secret called "regcred" to allow downloading image from private container registry.
6. Deploy docker image as a pod in K8s using kedgedeployment.yaml.

### If you want to deploy container directly, use the following syntax:
docker run -d --name kedge --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /var/lib/docker -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged youracr.azurecr.io/basekedge:preview

[Add explanation of each step and caveats]