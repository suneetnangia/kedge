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
   When we use --privileged flag for the container, Docker does not use default AppArmor profile (docker-default), a better solution would be define a custom AppArmor profile which permits only a limited set of resources for Docker container which needs to run another docker engine inside it. K8s also support this approach by applying specific AppArmour profiles via [App Armor Config](https://kubernetes.io/docs/tutorials/clusters/apparmor/) construct. You can also run IoT Edge container without --privileged flag but it does need additional Linux capabilities but again they can be restricted using custom AppArmor profile, see deployment section below for details. **This aspect of work is still in-progress.**

## Build and Deployment

### Build
Follow steps below to build an Azure IoT Edge container image, but if you do not want to build image yourself, skip to deploy section where you can use a prebuilt image.
1. Clone Repo:
   
   `git clone git@github.com:suneetnangia/kedge.git`

   `cd kedge`
2. Build Image: 
   
   `docker build -t <yourimagetag> .`
3. Upload Image: 
   
   `docker push <yourimagetag>`

### Deploy
Keep the connection string of Azure IoT Hub edge device ready, we will need it when configuring edge device on Azure IoT Edge runtime.

#### **On K8s:**
Note: In this deployment, a prior familiarity with K8s is needed. Also, we use [ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/) for storing IoT Edge device configuration but you may want to use [Secrets](https://kubernetes.io/docs/concepts/configuration/secret/) to make it more secure.

1. Authenticate and connect to existing K8s (if AKS, via cmd `az aks get-credentials --resource-group myResourceGroup --name myAKSCluster`)
2. Update config.toml with your edge device connection string (currently populated with dummy connection string).
3. Create ConfigMap to hold Azure IoT Edge configuration (config.toml content):

   `kubectl create configmap iotedge-config --from-file=config.toml`
4. Optionally, update kedgedeployment.yaml with your container image uri (from Build step above) otherwise it will use a [prebuilt](https://hub.docker.com/repository/registry-1.docker.io/suneetnangia/aziotedge) image from Docker Hub.
5. Deploy docker image as a pod:

   `kubectl apply -f .\kedgedeployment.yaml`
6. Check if Pod (`kedge-deployment-<generated id>`) is created and running:

   `kubectl get pods`

7. Check IoT Edge runtime services by logging into the container:

   `kubectl exec --stdin --tty <your-pod-name> /bin/bash`

   Once you are inside the container, you can run usual IoT Edge runtime checks.

#### **On Ubuntu Machine (WSL/2 is not supported):**

#### Setup IoT Edge Configuration:
1. Copy config.toml to the Linux machine (at /etc/aziot-init/config.toml) where you want to run IoT Edge Runtime container.
2. On the Linux machine, update config.toml with the IoT Edge device credentials (e.g. edge device connection string).
3. Optionally, replace image name 'suneetnangia/aziotedge:alpha1' in the below cmds with your image tag from Build step above.

#### Run With Privileged Flag

`sudo docker run -d --name kedge --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /var/lib/docker -v /sys/fs/cgroup:/sys/fs/cgroup:ro -v /etc/aziot-init/config.toml:/etc/aziot/config.toml --privileged suneetnangia/aziotedge:alpha1`

#### Run Without Privileged Flag:

`sudo docker run -d --name kedgenp --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup -v /etc/aziot-init/config.toml:/etc/aziot/config.toml --security-opt apparmor=unconfined --security-opt seccomp=unconfined --cap-add NET_ADMIN --cap-add SYS_ADMIN suneetnangia/aziotedge:alpha1`

## Disclaimer

Do not use this approach as-is to run Azure IoT Edge in production.
