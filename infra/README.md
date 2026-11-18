# Terraform lab

## Docker quickstart and environments

Run Terraform from the repository root. The quickstart uses nginx on port 8082
in its final configuration. To reproduce the port change, start with 8081,
apply and check the HTTP response, then restore 8082 and inspect the replacement
in the plan before applying again.

```sh
terraform -chdir=infra/quickstart init
terraform -chdir=infra/quickstart fmt -check
terraform -chdir=infra/quickstart validate
terraform -chdir=infra/quickstart plan
terraform -chdir=infra/quickstart apply
terraform -chdir=infra/quickstart show
docker rm -f tf-web
terraform -chdir=infra/quickstart plan
```

Apply each environment separately. The committed variable files contain only
public settings and use ports 8083 and 8084.

```sh
terraform -chdir=infra/envs/dev init
terraform -chdir=infra/envs/dev apply -var-file=dev.tfvars
terraform -chdir=infra/envs/staging init
terraform -chdir=infra/envs/staging apply -var-file=staging.tfvars
docker ps --filter name=tf-web
```

## State migration and drift

After the first dev apply, create a shared directory and substitute its
absolute path below. Confirm the state copy when prompted.

```sh
terraform -chdir=infra/envs/dev init -migrate-state -backend-config="path=/absolute/shared/dev.tfstate"
terraform -chdir=infra/envs/dev state list
terraform -chdir=infra/envs/dev state show module.webapp.docker_container.web
docker rm -f tf-web-dev
docker run -d --name tf-web-dev -p 8093:80 nginx:1.27
terraform -chdir=infra/envs/dev plan -refresh-only -var-file=dev.tfvars
terraform -chdir=infra/envs/dev plan -var-file=dev.tfvars
```

Docker assigns a new ID when it recreates the container, so Terraform sees the
original container as deleted. Remove the out-of-band container before
applying the corrective plan to avoid a name conflict.

```sh
docker rm -f tf-web-dev
terraform -chdir=infra/envs/dev apply -var-file=dev.tfvars
```

### Observed state migration and drift

Selected output from the lab run:

~~~text
terraform state list
module.webapp.docker_container.web
module.webapp.docker_image.app

docker port tf-web-dev 80/tcp
0.0.0.0:8093
[::]:8093

terraform plan -refresh-only -var-file=dev.tfvars
Note: Objects have changed outside of Terraform
# module.webapp.docker_container.web has been deleted

terraform plan -var-file=dev.tfvars
# module.webapp.docker_container.web will be created
+ external = 8083
Plan: 1 to add, 0 to change, 0 to destroy.
~~~

## Kubernetes previews

Use the local kind cluster and build the image from the repository.

```sh
kind create cluster --name devops-lab
docker build -t myapp:lab3-preview .
kind load docker-image myapp:lab3-preview --name devops-lab
```

Run one Terraform backend and one Terraform data directory per PR. The
following shell commands use an expiration date one day after creation.
For PowerShell, set the same variables with `$env:TF_DATA_DIR` and use
`(Get-Location).Path` to build the absolute path.

```sh
expires=2026-11-19

preview() {
  pr="$1"
  shift
  TF_DATA_DIR="$PWD/infra/preview/.terraform/pr-$pr" \
    terraform -chdir=infra/preview "$@"
}

for pr in 42 43; do
  preview "$pr" init -backend-config="path=state/pr-$pr.tfstate"
  preview "$pr" apply -var="pr_number=$pr" -var=image=myapp:lab3-preview \
    -var=owner=team-a -var="expires=$expires"
  kubectl --context kind-devops-lab -n "pr-$pr" rollout status deployment/myapp
  kubectl --context kind-devops-lab -n "pr-$pr" get deployment,pod,service
done

preview 42 destroy -var=pr_number=42 -var=image=myapp:lab3-preview \
  -var=owner=team-a -var="expires=$expires"
kubectl --context kind-devops-lab get namespace pr-42 --ignore-not-found -o name
kubectl --context kind-devops-lab -n pr-43 get deployment,pod,service
```

Namespaces scope each preview's Deployment and Service. The `owner` and
`expires` labels provide metadata for cleanup tooling. Cleanup in this
exercise is performed with `terraform destroy`.

### Observed preview verification

Selected output before destroying PR 42:

~~~text
NAME    STATUS   AGE   OWNER    EXPIRES
pr-42   Active   83s   team-a   2026-11-19
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp   1/1     1            1           83s

NAME                         READY   STATUS    RESTARTS   AGE
pod/myapp-759b776bd7-jb7b6   1/1     Running   0          83s

NAME            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/myapp   ClusterIP   10.96.62.16   <none>        80/TCP    83s
/health in pr-42: OK v0.2
NAME    STATUS   AGE   OWNER    EXPIRES
pr-43   Active   40s   team-a   2026-11-19
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp   1/1     1            1           40s

NAME                         READY   STATUS    RESTARTS   AGE
pod/myapp-759b776bd7-bmh25   1/1     Running   0          40s

NAME            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/myapp   ClusterIP   10.96.93.48   <none>        80/TCP    40s
/health in pr-43: OK v0.2
~~~

After Terraform destroyed preview 42, the namespace query with
--ignore-not-found -o name returned no output. Preview 43 still had its
Deployment, running Pod and Service:

~~~text
NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/myapp   1/1     1            1           95s

NAME                         READY   STATUS    RESTARTS   AGE
pod/myapp-759b776bd7-bmh25   1/1     Running   0          95s

NAME            TYPE        CLUSTER-IP    EXTERNAL-IP   PORT(S)   AGE
service/myapp   ClusterIP   10.96.93.48   <none>        80/TCP    95s
~~~
