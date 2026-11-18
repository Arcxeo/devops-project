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
