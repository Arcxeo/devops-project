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
