# Session 1: Git, CI/CD and Docker

## Part 1 -  Git Repository and Branching Workflow

Question 1. Why forbid direct pushes to main?
> Direct pushes to main should be forbidden to ensure that all changes are reviewed and tested before being merged. This reduces the risk of introducing bugs and maintains a stable main branch.

## Part 2 - Containerization

Build and run the application:

```sh
docker build -t myapp:0.1 .
docker run -d -p 3000:3000 --name myapp myapp:0.1
curl http://localhost:3000/health
docker logs myapp
docker exec -it myapp sh
```

Compare with the standard Node base image:

```sh
docker build --build-arg NODE_IMAGE=node:24 -t myapp:0.1-standard .
docker image ls myapp
```

Stop and remove the test container when finished:

```sh
docker rm -f myapp
```

Question 2. What is the difference between an image and a container?
> The difference between Docker image and a container it is like a a cake recipe(the immutable template) and the cake(the running container), one is the instruction to make the cake and the other is the final cake.

Question 3. Compare the size of your image with a non-slim base image. What do you observe?
> On this machine, `docker image ls myapp` reports about 252 MB for `myapp:0.1` (Alpine) and 1.64 GB for `myapp:0.1-standard` (`node:24`), so the standard image is approximately 6.5 times larger. Exact values can vary by Docker version and platform. The standard image contains a full Linux userland and more system tools, while Alpine keeps only a minimal set of packages. This reduces download time, storage use, and the potential attack surface, although Alpine can sometimes require extra compatibility work for native dependencies.

## Part 3 - CI Pipeline

The GitHub Actions workflow installs dependencies, runs lint and tests, and builds the Docker image for every pull request. After a successful push to `main`, it also publishes the image to GitHub Container Registry with the commit SHA as its tag.

Question 4. Why tag the image with the commit SHA rather than `latest`?
> A commit SHA is immutable and uniquely identifies the exact source code used to build an image. It makes deployments reproducible and provides direct traceability from an image back to its commit and pipeline run. The `latest` tag is mutable, ambiguous, and can point to a different image over time.

Question 5. What does "fail fast" mean in a pipeline?
> Fail fast means running quick checks early and stopping the pipeline as soon as one fails. This gives developers rapid feedback and avoids spending time and resources on later steps, such as building or publishing an image, when the code is already known to be invalid.

# Session 2: Kubernetes, Multi-environment Deployment and Audit

## Part 1 - Local Cluster Setup

Question 1. What is the role of a namespace? Does it provide strong security isolation by itself?
> A namespace is a logical partition inside a Kubernetes cluster. It groups namespaced resources such as Pods, Deployments, Services, ConfigMaps, and Secrets. Namespaces help organize workloads by team or environment, avoid naming conflicts, scope RBAC permissions and quotas, and make resources easier to manage.
>
> A namespace does not provide strong security isolation by itself. Workloads in different namespaces still share the same cluster, nodes, kernel, and network by default. Stronger isolation requires complementary controls such as RBAC, NetworkPolicies, Pod Security Admission, resource quotas, separate service accounts, admission policies, and, for stricter trust boundaries, separate clusters.
