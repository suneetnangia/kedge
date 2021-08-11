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

   When running Docker in Docker (dind) without [rootless](https://docs.docker.com/engine/security/rootless/) mode, Docker engine makes use of Linux kernel level security module called [AppArmor](https://help.ubuntu.com/community/AppArmor). As AppArmor is a kernel level security module and kernel is not virtualized in containers, the container which host IoT Edge runtime needs to ensure it can access AppArmor service of the Linux parent machine.
   The simplest solution to this problem is to run IoT Edge runtime hosting container with a --privileged flag, which will allow AppArmour service to run inside it, accessing parent machine's kernel module and allowing IoT Edge Moby container engine to make use of it. This approach however gives elevated access to the IoT Edge runtime hosting container to the host machine resources which is not recommended.
   Docker engine creates a default AppArmor profile (docker-default) and attach this profile for every container it starts unless it is overridden by a custom profile explicitly. When we use --privileged flag for the container, Docker engine does not attach any AppArmor profile, leaving the container as a high risk process on the parent machine.
   There's another Linux kernel level security feature called [SecComp](https://docs.docker.com/engine/security/seccomp/) which is used to restrict the actions available to the code inside the containers. You can restrict what actions are allowed from the container e.g. calls to mount/unmount or access to certain directories. Similar to AppArmor, Docker engine creates a default SecComp profile and attach this profile for every container it starts unless it is overridden by a custom profile explicitly. When we use --privileged flag for the container, Docker engine does not attach any SecComp profile, leaving the container as a high risk process on the parent machine.

   A better solution to the above challenges would be define a custom AppArmor and SecComp profile derived from the default profiles, which permits access to the a limited set of resources on the Linux parent machine. These profiles are available to use in this repo as `aziot-aa-profile.conf` and `aziot-sc-profile.json`. Please be aware that you may need to further restrict these profiles for your use cases where feasible.

   As a side note, K8s also support this approach by applying specific AppArmour and SecComp profiles via [App Armor Config](https://kubernetes.io/docs/tutorials/clusters/apparmor/) and [SecComp Config](https://kubernetes.io/docs/tutorials/clusters/seccomp/) constructs respectively.

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

[TODO: Update deployment manifest to use custom AppArmor and SecComp profiles, the way they are configured is being changes in K8s.]

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

#### Setup IoT Edge Configuration

1. Copy config.toml to the parent Linux machine (at /etc/aziot-init/config.toml) where you want to run IoT Edge Runtime container.
2. On the parent Linux machine, update config.toml with the IoT Edge device credentials (e.g. edge device connection string).
3. Optionally, replace image name 'suneetnangia/aziotedge:alpha1' in the below cmds with your image tag from Build step above.

#### Run Without AppArmor/SecComp

`sudo docker run -d --name kedgenp --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup -v /etc/aziot-init/config.toml:/etc/aziot/config.toml --security-opt apparmor=unconfined --security-opt seccomp=unconfined --cap-add NET_ADMIN --cap-add SYS_ADMIN suneetnangia/aziotedge:alpha1`

#### Run With AppArmor/SecComp

Before you run the below cmd, please see [here](https://docs.docker.com/engine/security/apparmor/) to deploy custom AppArmor `aziot-aa-profile.conf` profile on the parent Linux machine. Regarding SecComp profile, it just needs to be present at the path specified in the Docker run command.

`sudo docker run -d --name kedgenp --tmpfs /tmp --tmpfs /run --tmpfs /run/lock -v /sys/fs/cgroup:/sys/fs/cgroup -v /etc/aziot-init/config.toml:/etc/aziot/config.toml --security-opt apparmor=docker-aziotedge --security-opt seccomp=./aziot-sc-profile.json --cap-add NET_ADMIN --cap-add SYS_ADMIN suneetnangia/aziotedge:alpha1`

## Disclaimer

Do not use this approach as-is to run Azure IoT Edge in production.
