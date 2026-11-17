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
