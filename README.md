# DevOps Labs

## Group members

- Ali Belhassen
- Arnaud Van Eeckhoven
- Nicolas Papleux
- Romain Dangin

We used AI as a guide during the labs.

## Session 1: Git, CI/CD and Docker

### Part 1 - Git repository and branching workflow

#### 1. Why forbid direct pushes to `main`?

Pull requests give someone else a chance to review the change and let CI run before it reaches `main`. A direct push can put a broken commit on the shared branch straight away.

### Part 2 - Containerization

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

#### 2. What is the difference between an image and a container?

The image contains the application, its dependencies and the default command. A container is an instance of that image, with its own processes and a writable layer. We can start several containers from the same image.

#### 3. Compare the size of your image with a non-slim base image. What do you observe?

Our Alpine build was about 252 MB. The build with `node:24` was 1.64 GB, roughly six and a half times larger. The standard base includes more system packages.

### Part 3 - CI pipeline

Our GitHub Actions workflow runs `npm ci`, the linter, the tests and the Docker build on each Pull Request. A push to `main` also publishes the image to GitHub Container Registry.

#### 4. Why tag the image with the commit SHA rather than `latest`?

The commit SHA tells us which revision an image was built from. If something breaks, we can go back to that commit and its CI run. `latest` can point at a different build by then.

#### 5. What does "fail fast" mean in a pipeline?

Run the quick checks first and stop when one fails. If the tests are red, we can skip the Docker build and fix the tests.

## Session 2: Kubernetes, Multi-environment Deployment and Audit

### Part 1 - Local cluster setup

We created a local cluster named `devops-lab` with kind. We checked that the control-plane node was ready and that the three namespaces were active in the `kind-devops-lab` context.

Useful checks:

```sh
kind get clusters
kubectl cluster-info --context kind-devops-lab
kubectl get nodes --context kind-devops-lab
kubectl get namespace dev staging prod --context kind-devops-lab
```

#### 1. What is the role of a namespace? Does it provide strong security isolation by itself?

We used `dev`, `staging` and `prod` to keep each environment's Pods and Services separate. They still share a cluster, and Pods can usually reach each other under the default network setup. RBAC controls API access and NetworkPolicies can restrict traffic between workloads.

### Part 2 - First deployment

The Kubernetes manifests are in `k8s/base/`. The Deployment starts three copies of `myapp:0.1`, and the Service exposes them on port 80 inside the cluster.

Commands used for the deployment:

```sh
kind load docker-image myapp:0.1 --name devops-lab
kubectl apply -f k8s/base/ -n dev
kubectl get all -n dev
kubectl port-forward svc/myapp 8080:80 -n dev
curl http://localhost:8080/health
```

#### 2. Why does Kubernetes recreate the deleted Pod? Which component is responsible?

The Deployment asks for three replicas. After we delete a Pod, the ReplicaSet controller sees only two and starts a replacement. The replacement gets its own name.

### Part 3 - Probes, resources and configuration

The Deployment now checks `/health` with readiness and liveness probes. It also defines CPU and memory requests and limits. `APP_ENV` comes from `myapp-config`, while the fake `API_KEY` comes from `myapp-secret`.

#### 3. What is the difference between a readiness and a liveness probe? What happens to traffic when readiness fails?

Readiness controls whether the Pod receives traffic from the Service. If the check fails, the Pod stays up but stops receiving that traffic. Repeated liveness failures cause the kubelet to restart the container.

#### 4. Is a Kubernetes Secret encrypted by default? How would you improve this?

Values in the `data` field are base64-encoded, which anyone who can read them can decode. We would enable encryption at rest for etcd, restrict access with RBAC and keep real credentials in a secret manager.

### Part 4 - Multiple environments with Kustomize

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

#### 5. How does this pattern help with hybrid or multi-cloud deployments? What would differ between a real on-prem cluster and a cloud cluster?

We can share the Deployment and Service and keep each environment's differences in its overlay. A cloud overlay might use a managed load balancer and storage class. An on-prem overlay would use the ingress and storage available in that cluster.

### Part 5 - Rolling update and rollback

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

#### 6. Why did the broken rollout not take down the application?

The new Pod could never pull `myapp:broken`, so it never became ready. The rolling update kept the old `0.2` Pod serving requests. We still had to run `kubectl rollout undo` to restore the Deployment.

### Part 6 - Audit and traceability

The `prod` Deployment has annotations for the Git commit, the GitHub Actions run, the owner and the ticket. The RBAC manifests in `k8s/rbac/` create a `viewer` ServiceAccount that can only read Pods in `dev`.

```sh
kubectl apply -k k8s/overlays/prod
kubectl get events -n prod --sort-by=.metadata.creationTimestamp
kubectl describe deployment myapp -n prod
kubectl apply -k k8s/rbac
kubectl auth can-i list pods -n dev --as=system:serviceaccount:dev:viewer
kubectl auth can-i delete pods -n dev --as=system:serviceaccount:dev:viewer
```

Observed RBAC results:

```text
list pods:    yes
get pods:     yes
delete pods:  no
list secrets: no
```

The production trace used in this lab is:

```text
Pod -> ReplicaSet -> Deployment
commit: 73637f31c7329ec4d91521f7cfd72e8a838f2771
pipeline: https://github.com/Arcxeo/devops-project/actions/runs/44121519990
owner: team-a
ticket: OPS-123
```

#### 7. Starting from a Pod running in production, how can you find the commit, the reviewer and the pipeline run that produced it?

Follow `ownerReferences` from the Pod to its ReplicaSet and then to the Deployment. The Deployment annotations give us the commit and the Actions run. From the commit on GitHub, we can open the PR and look up who reviewed it.

#### 8. Why is manual `kubectl edit` in production a traceability risk?

`kubectl edit` updates the cluster immediately, so the diff never goes through Git, review or CI. The next deployment can overwrite it, and the team may struggle to explain when or why it changed.

## Session 3: Terraform, Environments and Ephemeral Previews

See the [Terraform lab notes](infra/README.md) for the commands and test output.

### Part 1 - First Terraform Configuration

#### 1. What did Terraform propose after you deleted the container by hand? What is this situation called?

After we deleted `tf-web`, Terraform's next plan proposed creating it again on port `8082`. The configuration still declared the container, but Docker no longer had it. That's drift.

#### 2. Why should the state file never be committed to Git?

State can include passwords, internal addresses and resource IDs. If it gets into Git, removing the file in a later commit leaves the earlier copy in history. A shared backend can restrict access, encrypt state and lock it during updates.

### Part 2 - Variables, Outputs and Modules

#### 3. What are the advantages of one folder and one state per environment compared to workspaces?

For this lab we ran Terraform in `infra/envs/dev` or `infra/envs/staging`, so the command itself made the target clear. Each directory can have its own variables, backend and permissions. With CLI workspaces, both environments share a configuration and the selected workspace decides which state Terraform opens.

### Part 3 - State Management

#### 4. Why is a remote backend with locking essential for a team? Which problems does it prevent?

Everyone needs to work from the same state. The lock stops two operations from writing it at once and losing each other's changes. We used a shared local path for the exercise. In a team we'd use a remote backend with locking and version history.

#### 5. What information in a state file can be sensitive?

Passwords, API tokens and connection strings can end up in state, along with private addresses and resource IDs. Terraform can hide a sensitive value in the terminal while still storing it in state or a saved plan.

### Part 4 - Ephemeral Environment per Pull Request

#### 6. What could go wrong if the preview environment is never destroyed? List three mitigations.

An old preview keeps using cluster resources and can leave an outdated build reachable. We'd handle it in three ways.

1. Destroy the preview when the PR closes or merges.
2. Give it an expiry date and schedule a job to clean up expired namespaces.
3. Assign an owner and use resource quotas to limit what each preview can consume.

### Part 5 - Terraform in CI with Security Scanning

#### 7. Why run plan on a Pull Request but apply only after merge?

A plan lets reviewers see what Terraform would add, change or delete before anything happens to the shared environment. An apply after merge uses the approved revision and can go through the deployment environment's approval rules.

#### 8. Why should a CI pipeline use short-lived credentials (OIDC) rather than long-lived access keys?

With OIDC, a job exchanges its identity for credentials that expire. We can limit which repository, branch or environment can request them and what they can do. There is no permanent access key to store in the repository's secrets.

## Session 4: Observability, Alerting and Incident Response

### Part 1 - Instrument the Application

The application now exposes Prometheus metrics on `/metrics` and writes one JSON log line per request to stdout. We added two test endpoints: `/slow` waits for a random time up to 2 seconds, and `/error` returns HTTP 500 about 30% of the time.

Commands used to test and build it:

```sh
npm ci
node app.js
curl localhost:3000/slow
curl localhost:3000/error
curl localhost:3000/metrics
docker build -t myapp:$(git rev-parse HEAD) .
```

Over 200 local calls to `/error`, we got 70 HTTP 500 responses (35%). The counters in `/metrics` matched the calls:

```text
http_requests_total{method="GET",route="/slow",status="200"} 8
http_requests_total{method="GET",route="/error",status="500"} 70
http_requests_total{method="GET",route="/error",status="200"} 130
```

#### 1. Why is it a problem to use a user ID or a full URL containing IDs as a metric label?

Prometheus stores one time series per combination of label values, so each new ID creates more series, multiplied by the number of buckets for a histogram. Memory use grows and queries slow down. We use the Express route pattern as the label, with `unmatched` for unknown paths, and keep the real path in the logs.

#### 2. Why log to stdout in JSON rather than to a file in plain text?

A file inside the container is lost with the Pod. With stdout, Kubernetes collects the output, `kubectl logs` can show it and an agent can send it to a central store. JSON fields such as `status` or `level` can be filtered directly, without parsing free text.
