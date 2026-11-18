variable "pr_number" {
  type = string

  validation {
    condition     = can(regex("^[1-9][0-9]{0,58}$", var.pr_number))
    error_message = "Use a positive PR number that fits in a Kubernetes namespace name."
  }
}

variable "image" {
  type = string
}

variable "owner" {
  type = string
}

variable "expires" {
  type        = string
  description = "Expiration date in YYYY-MM-DD format for cleanup tooling."

  validation {
    condition     = can(formatdate("YYYY-MM-DD", "${var.expires}T00:00:00Z"))
    error_message = "Use a valid expiration date in YYYY-MM-DD format."
  }
}

variable "kubeconfig" {
  type    = string
  default = "~/.kube/config"
}

variable "kube_context" {
  type    = string
  default = "kind-devops-lab"
}
