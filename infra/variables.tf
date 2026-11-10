variable "region" {
  type    = string
  default = "us-east-1" # CloudFront certificates must live in us-east-1, so everything does.
}

variable "owner" { type = string }

variable "github_repo" {
  type        = string
  description = "owner/name of the repo allowed to deploy, e.g. mk7git-hub/devops-cloud-portfolio"
}

variable "github_owner_id" {
  type        = string
  description = "Immutable numeric GitHub owner ID (GitHub's OIDC subject includes it for new repos)"
}

variable "github_repo_id" {
  type        = string
  description = "Immutable numeric GitHub repository ID"
}

variable "domain_name" {
  type        = string
  default     = ""
  description = "Optional custom domain with a Route 53 hosted zone. Empty = use the CloudFront URL."
}

variable "reserved_concurrency" {
  type        = number
  default     = -1
  description = "Lambda reserved concurrency. New accounts have a limit of 10 and AWS keeps 10 unreserved, so -1 (off) until the limit is raised; then 5 caps abuse."
}

variable "api_rate_limit" {
  type    = number
  default = 10
}

variable "alert_email" {
  type        = string
  sensitive   = true
  description = "Where CloudWatch alarms are emailed. Set as a sensitive variable in HCP Terraform, never committed."
  validation {
    # Fail in the plan with a clear message instead of halfway through apply (SNS rejects bad addresses).
    condition     = can(regex("^[^@\\s\"]+@[^@\\s\"]+\\.[A-Za-z]{2,}$", var.alert_email))
    error_message = "alert_email must be a bare email address: no quotes, no spaces, HCL unticked."
  }
}

variable "request_spike_threshold" {
  type        = number
  default     = 10000
  description = "CloudFront requests per 5 minutes before the spike alarm fires"
}
