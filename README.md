# DevOps Labs

## Group members

- Ali Belhassen
- Arnaud Van Eeckhoven
- Nicolas Papleux
- Romain Dangin

# Session 1: Git, CI/CD and Docker

## Part 1 - Git repository and branching workflow

Question 1. Why forbid direct pushes to `main`?
> A direct push skips the Pull Request review and its checks. If the commit is broken, `main` is broken too. With a protected branch, changes have to pass the tests and be reviewed before they are merged.

## Part 2 - Containerization

Commands used to build and run the application:

```sh
docker build -t myapp:0.1 .
docker run -d -p 3000:3000 --name myapp myapp:0.1
curl http://localhost:3000/health
docker logs myapp
docker exec -it myapp sh
```

We also built the application with the standard Node image to compare sizes:

```sh
docker build --build-arg NODE_IMAGE=node:24 -t myapp:0.1-standard .
docker image ls myapp
```

Cleanup command:

```sh
docker rm -f myapp
```

Question 2. What is the difference between an image and a container?
> An image is like a cake recipe: it contains everything needed to create the application environment. A container is the cake made from that recipe. The image does not change, while the running container has its own processes and writable data.

Question 3. Compare the size of your image with a non-slim base image. What do you observe?
> On our machine, the Alpine image was about 252 MB. The same application built with `node:24` was 1.64 GB, around 6.5 times larger. Alpine contains fewer system packages, which explains most of the difference. The exact size can change depending on the Docker version and the computer.

## Part 3 - CI pipeline

Our GitHub Actions workflow runs `npm ci`, the linter, the tests and the Docker build on each Pull Request. A push to `main` also publishes the image to GitHub Container Registry.

Question 4. Why tag the image with the commit SHA rather than `latest`?
> A SHA points to one exact commit. If an image fails in production, we can find the source code and the pipeline run that built it. The `latest` tag can move each time a new image is published, so it does not give us that traceability.

Question 5. What does "fail fast" mean in a pipeline?
> It means running the quick checks first and stopping as soon as one fails. For example, if the tests fail, there is no reason to continue with the Docker build or publish the image.

# Session 2: Kubernetes, Multi-environment Deployment and Audit

## Part 1 - Local cluster setup

We created a local cluster named `devops-lab` with kind. The current context is `kind-devops-lab`, the control-plane node is `Ready`, and the `dev`, `staging` and `prod` namespaces are active.

Useful checks:

```sh
kind get clusters
kubectl cluster-info --context kind-devops-lab
kubectl get nodes --context kind-devops-lab
kubectl get namespace dev staging prod --context kind-devops-lab
```

Question 1. What is the role of a namespace? Does it provide strong security isolation by itself?
> A namespace separates resources inside the same cluster. We use one namespace for each environment so that, for example, the `dev` Pods and Services do not get mixed with the ones in `prod`.
>
> A namespace alone is not a strong security boundary. The namespaces still use the same cluster and nodes, and network traffic is allowed by default. We would also need RBAC and NetworkPolicies. For workloads that must be completely separated, using different clusters is safer.

## Part 2 - First deployment

The Kubernetes manifests are in `k8s/base/`. The Deployment starts three copies of `myapp:0.1`, and the Service exposes them on port 80 inside the cluster.

Commands used for the deployment:

```sh
kind load docker-image myapp:0.1 --name devops-lab
kubectl apply -f k8s/base/ -n dev
kubectl get all -n dev
kubectl port-forward svc/myapp 8080:80 -n dev
curl http://localhost:8080/health
```

Question 2. Why does Kubernetes recreate the deleted Pod? Which component is responsible?
> The Deployment says that three replicas must be running. When a Pod is deleted, the ReplicaSet sees that only two are left and creates a replacement. The ReplicaSet controller, running in `kube-controller-manager`, handles this reconciliation. The new Pod has a different name because it is a new object.

## Part 3 - Probes, resources and configuration

The Deployment now checks `/health` with readiness and liveness probes. It also defines CPU and memory requests and limits. `APP_ENV` comes from `myapp-config`, while the fake `API_KEY` comes from `myapp-secret`.

Question 3. What is the difference between a readiness and a liveness probe? What happens to traffic when readiness fails?
> Readiness tells Kubernetes whether a Pod can receive traffic. When it fails, the Pod keeps running but the Service removes it from its endpoints. Liveness checks whether the application is stuck or unhealthy. When liveness fails several times, Kubernetes restarts the container.

Question 4. Is a Kubernetes Secret encrypted by default? How would you improve this?
> No. The value stored in a Secret manifest is only base64-encoded, not encrypted. Secrets can also be stored unencrypted in etcd unless encryption at rest is configured. We would enable etcd encryption, restrict access with RBAC and, for a real production setup, use an external secret manager instead of keeping secret values in Git.

## Part 4 - Multiple environments with Kustomize

The files in `k8s/base/` contain the common configuration. Each folder in `k8s/overlays/` changes the namespace, the `env` label, `APP_ENV` and the replica count. We use one replica in `dev`, three in `staging` and five in `prod`.

Commands used to preview and deploy the overlays:

```sh
kubectl kustomize k8s/overlays/dev
kubectl kustomize k8s/overlays/staging
kubectl kustomize k8s/overlays/prod
kubectl apply -k k8s/overlays/dev
kubectl apply -k k8s/overlays/staging
kubectl apply -k k8s/overlays/prod
kubectl get deployment -A -l app=myapp
```

Question 5. How does this pattern help with hybrid or multi-cloud deployments? What would differ between a real on-prem cluster and a cloud cluster?
> The base keeps the application configuration the same everywhere, while each overlay contains only the changes needed for one target. This avoids maintaining three copies of the same Deployment and Service.
>
> In a real setup, the overlays could select different StorageClasses, ingress settings or cloud load balancers. An on-prem cluster would use the storage, network and registry available in the local infrastructure, while a cloud cluster would usually use services provided by that cloud. Credentials and cluster access would also be managed separately.

## Part 5 - Rolling update and rollback

For version `0.2`, `/health` returns `OK v0.2`. We built the new image, loaded it into kind and changed the `dev` overlay from `myapp:0.1` to `myapp:0.2`. Requests continued to succeed while Kubernetes replaced the Pod.

We then applied the nonexistent tag `myapp:broken` on purpose. The new Pod stayed in `ImagePullBackOff`, while the previous `0.2` Pod continued serving traffic. `kubectl rollout undo` restored the Deployment.

Commands used during the test:

```sh
docker build -t myapp:0.2 .
kind load docker-image myapp:0.2 --name devops-lab
kubectl apply -k k8s/overlays/dev
kubectl rollout status deployment/myapp -n dev
kubectl rollout history deployment/myapp -n dev
kubectl rollout undo deployment/myapp -n dev
```

Question 6. Why did the broken rollout not take down the application?
> The Deployment uses the `RollingUpdate` strategy. Kubernetes waits for the new Pod to become ready before removing the old one. The Pod using the broken image never became ready, so the existing `0.2` Pod stayed in the Service and kept answering requests. Kubernetes did not fix the bad image automatically; we still had to roll back the Deployment.
