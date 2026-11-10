terraform {
  required_version = ">= 1.6"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "~> 5.70" }
    archive = { source = "hashicorp/archive", version = "~> 2.4" }
  }
  # Partial config: values live in backend.hcl (copy backend.hcl.example), so no account IDs are committed.
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = { Project = "devops-cloud-portfolio", Owner = var.owner, ManagedBy = "terraform" }
  }
}
