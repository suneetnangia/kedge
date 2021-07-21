# KEdge, a Kubernetes based Azure IoT Edge deployment.

This repo demonstrates an experimental deployment of IoT Edge runtime 1.2 in container and on K8s.

## Approach

![alt text](SimpleK8sEdge.png "Edge on K8s")

In this approach IoT Edge runtime is deployed in a container as-is with out any code changes, which is a least intrusive way of running it in a container or a Pod. IoT Edge runtime is a container orchestrator which manages edge modules(containers) lifecycle, due to this requirement it needs direct access to the container engine like Moby. If we have to run IoT Edge runtime in a container (hosting) we will have to make sure there's a container runtime available inside that hosting container, so that Edge runtime can run modules as containers within the hosting container in a nested manner (aka Docker in Docker).

## Challenges

There were a few challenges which were presented during porting of IoT Edge runtime in a container, predominantly:

1. **IoT Edge runtime dependency on [systemd](https://en.wikipedia.org/wiki/Systemd) service management module in Linux.**

   IoT Edge makes use of systemd module for service management on the host OS, this allows various runtime services to be started at boot time and restarted if they are crashed as per their unit configuration. By default, systemd is not installed on the container which resulted in failed IoT Edge deployment. As solution to this problem, [Dockerfile](/Dockerfile) to build IoT Edge runtime image was updated to install systemd and run it as PID1 in a container.
2. **Ringfencing**

   When running Docker in Docker (dind), inner Docker needs certain level of access at the host level e.g. AppArmor. AppArmor is a kernel level module hence it is not virtualized at the container level unlike filesystem, network etc. The simplest solution to this problem was to run hosting container with --privileged flag, which will allow AppArmour service to run inside it, allowing IoT Edge Moby container engine to make use of it. This approach however gives elevated access to the hosting docker container on the host machine resources which is not recommended.
   When we use --privileged flag for the container, Docker does not use default AppArmor profile (docker-default), a better solution would be define a custom AppArmor profile which permits only a limited set of resources for Docker container which needs to run another docker engine inside it. K8s also support this approach by applying specific AppArmour profiles and Linux capabilities via [pod security policy](https://kubernetes.io/docs/concepts/policy/pod-security-policy/) construct. **This aspect of work is still in-progress.**

## Deployment

Note:

When you build the container image below, it copies the IoT edge config.toml file from local directory to the predefined location in the container image. Please update credentials in the local config.toml file before building image, this will allow image to work as a specific edge device when started. More work is required in this area to allow injection of device credentials via Docker environment variables, current implementation risks exposing connection string if image is leaked, certficates will be more secure option here.

### Follow the steps below to deploy IoT Edge runtime along with a stock temperature sensor module to the existing K8s cluster as a pod

In this deployment, prior familiarity with K8s will be needed.

1. Clone this repo, change directory to this repo, locally.
2. Authenticate and connect to existing K8s cluster via cmd 'az aks get-credentials --resource-group myResourceGroup --name myAKSCluster'
3. Update config.toml with your device connection string (currently populated with dummy connection string).
4. Build docker container image (e.g. "docker build -t youracr.azurecr.io/basekedge:preview .").
5. Update kedgedeployment.yaml with your container registry and image uri.
6. Create K8s image pull secret called "regcred" to allow downloading image from private container registry.
7. Deploy docker image as a pod in K8s using kedgedeployment.yaml.

### Alternatively, if you want to run container directly on Ubuntu (WSL/2 is not supported), use the following command lines

**Prerequisites:**

1. Clone this repo, change directory to this repo, locally.
2. Update local config.toml with your device connection string/certs (by default populated with pseudo connection string).

**With Privilege Flag:**

docker build -t aziotedgecontainer .

docker run -d --name kedge --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /var/lib/docker -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged aziotedgecontainer

**Without  Privilege Flag**

docker build -t aziotedgecontainer .

sudo docker run -d --name kedgenp --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup --security-opt apparmor=unconfined --security-opt seccomp=unconfined --cap-add NET_ADMIN --cap-add SYS_ADMIN aziotedgecontainer


## Disclaimer

This is not an official guidance to run Azure IoT Edge in production.
