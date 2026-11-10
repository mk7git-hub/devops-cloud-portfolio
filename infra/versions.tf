terraform {
  required_version = ">= 1.6"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.70" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
  # HCP Terraform runs plan/apply and stores state. Organization comes from TF_CLOUD_ORGANIZATION
  # when running locally; VCS-driven runs use the workspace they belong to.
  cloud {
    workspaces { name = "devops-cloud-portfolio" }
  }
}

# Credentials: none here. HCP Terraform injects short-lived role credentials per run
# (workspace env vars TFC_AWS_PROVIDER_AUTH=true and TFC_AWS_RUN_ROLE_ARN).
provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "devops-cloud-portfolio", Owner = var.owner, ManagedBy = "hcp-terraform" }
  }
}
