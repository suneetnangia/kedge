# KEdge, a Kubernetes based Azure IoT Edge deployment.

This repo demonstrates an experimental deployment of IoT Edge runtime 1.2 in container and on K8s.

## Approach

![alt text](SimpleK8sEdge.png "Edge on K8s")

In this approach IoT Edge runtime is deployed in a container as-is with out any code changes, this is a least intrusive way to run IoT Edge in a container or a Pod.
To provide some context, IoT Edge runtime is a container orchestrator which manages edge modules' (containers) lifecycle, due to this requirement it needs direct access to the container engine like [Moby](https://mobyproject.org/). There were multiple ways to give access to Docker API from within a container, the option used in this solution deploys container runtime (Moby) within a parent container where edge runtime also installed (aka Docker in Docker(dind)). This option was favoured over others due to two main reasons, firstly, it decouples the parent container engine/runtime used by K8s or any other orchestrator which may not be supported by IoT Edge runtime and secondly, it keeps containers/modules created by IoT Edge runtime within the bounds of parent container keeping parent container engine/runtime in clean state. Another key point to know is that it does not runs IoT Edge runtime modules/services or custom modules in K8s native manner i.e. they don't run as separate pods or scale across the nodes, that will need changes in underlying IoT Edge runtime v1.2 codebase.

## Challenges

There were a few challenges which were presented during porting of IoT Edge runtime in a container, predominantly:

1. **IoT Edge runtime dependency on [systemd](https://en.wikipedia.org/wiki/Systemd) service management module in Linux.**

   When installed on Linux OS, IoT Edge makes use of systemd module for service management, this allows various runtime services to be started at boot time and restarted if they are crashed as per their systemd unit configuration. By default, systemd is not installed in the container which resulted in failed IoT Edge deployment. As solution to this problem, [Dockerfile](/Dockerfile) to build IoT Edge runtime image was updated to install systemd and run it as PID1 inside the container.

2. **Ringfencing**

   When running Docker in Docker (dind), inner Docker needs certain level of access at the host level e.g. [AppArmor](https://help.ubuntu.com/community/AppArmor). AppArmor is a kernel level security module hence it is not virtualized at the container level unlike filesystem, network etc. The simplest solution to this problem was to run hosting container with --privileged flag, which will allow AppArmour service to run inside it, allowing IoT Edge Moby container engine to make use of it. This approach however gives elevated access to the hosting docker container on the host machine resources which is not recommended.
   When we use --privileged flag for the container, Docker does not use default AppArmor profile (docker-default), a better solution would be define a custom AppArmor profile which permits only a limited set of resources for Docker container which needs to run another docker engine inside it. K8s also support this approach by applying specific AppArmour profiles via [App Armor Config](https://kubernetes.io/docs/tutorials/clusters/apparmor/) construct. You can also run IoT Edge container without --privileged flag but it does need additional Linux capabilities which can be further restricted, see deployment section below for details. **This aspect of work is still in-progress.**

## Deployment

Note:

When you build the container image below, it copies the IoT edge config.toml file from local directory to the predefined location in the container image. Please update credentials in the local config.toml file before building image, this will allow image to work as a specific edge device when started. More work is required in this area to allow injection of device credentials via Docker environment variables, current implementation risks exposing connection string if image is leaked, certficates will be more secure option here.

### Follow the steps below to deploy IoT Edge runtime along with a stock temperature sensor module to the existing K8s cluster as a pod

In this deployment, prior familiarity with K8s will be needed.

1. Clone this repo, change directory to this repo, locally.
2. Authenticate and connect to existing K8s  (if AKS, via cmd 'az aks get-credentials --resource-group myResourceGroup --name myAKSCluster')
3. Update config.toml with your device connection string (currently populated with dummy connection string).
4. Build docker container image (e.g. "docker build -t youracr.azurecr.io/basekedge:preview .").
5. Update kedgedeployment.yaml with your container registry and image uri.
6. Create K8s image pull secret called "regcred" to allow downloading image from private container registry.
7. Deploy docker image as a pod in K8s using kedgedeployment.yaml.

### Alternatively, if you want to run container directly on Ubuntu (WSL/2 is not supported), use the following command lines

**Prerequisites:**

1. Clone this repo, change directory to this repo, locally.
2. Update local config.toml with your device connection string/certs (pre-populated with pseudo connection string).
3. docker build -t aziotedgecontainer .

**With Privileged Flag:**

docker run -d --name kedge --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /var/lib/docker -v /sys/fs/cgroup:/sys/fs/cgroup:ro --privileged aziotedgecontainer

**Without Privileged Flag**

sudo docker run -d --name kedgenp --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup --security-opt apparmor=unconfined --security-opt seccomp=unconfined --cap-add NET_ADMIN --cap-add SYS_ADMIN aziotedgecontainer

## Disclaimer

This is not an official guidance to run Azure IoT Edge in production.
