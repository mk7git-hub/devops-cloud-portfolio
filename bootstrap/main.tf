# One-time bootstrap (local state, run by you): lets HCP Terraform assume an AWS role per run
# via OIDC "dynamic provider credentials". No AWS access keys are stored in HCP Terraform or GitHub.
#
# The site's Terraform creates two IAM roles (the counter Lambda's and the GitHub deploy role), so
# the run role needs some IAM. It is boxed in three ways:
#   1. it can only create or change roles named devops-portfolio-*, and only if they carry the
#      workload boundary below, so nothing it creates can do more than read/write the counter,
#      write logs and deploy the site;
#   2. its own boundary denies changes to itself, to either boundary policy, and boundary removal;
#   3. its trust only accepts runs of the one HCP workspace.
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.70" }
    tls = { source = "hashicorp/tls", version = "~> 4.0" }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { Project = "devops-cloud-portfolio", ManagedBy = "terraform-bootstrap" }
  }
}

variable "hcp_organization" {
  type        = string
  description = "Your HCP Terraform organization name"
}

variable "hcp_project" {
  type    = string
  default = "Default Project"
}

variable "hcp_workspace" {
  type    = string
  default = "devops-cloud-portfolio"
}

data "aws_caller_identity" "me" {}

data "tls_certificate" "hcp" {
  url = "https://app.terraform.io"
}

# One per account. If it already exists, import it first (see README: Deploy it yourself).
resource "aws_iam_openid_connect_provider" "hcp" {
  url             = "https://app.terraform.io"
  client_id_list  = ["aws.workload.identity"]
  thumbprint_list = [data.tls_certificate.hcp.certificates[0].sha1_fingerprint]
}

locals {
  prefix   = "devops-portfolio"
  acct     = data.aws_caller_identity.me.account_id
  run_role = "hcp-run-${local.prefix}" # deliberately outside devops-portfolio-*, so it can't edit itself
  roles    = "arn:aws:iam::${local.acct}:role/${local.prefix}-*"
}

# Ceiling for every role the workspace creates: the counter Lambda and the GitHub deploy role.
resource "aws_iam_policy" "workload_boundary" {
  #checkov:skip=CKV_AWS_355:A boundary is a ceiling, not a grant; the roles' own policies scope resources
  #checkov:skip=CKV_AWS_288:Ceiling only; the deploy role policy grants GetObject on the site bucket alone
  #checkov:skip=CKV_AWS_290:Ceiling only; writes are scoped in each role's own policy
  name = "${local.prefix}-workload-boundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "dynamodb:GetItem", "dynamodb:UpdateItem",
        "logs:CreateLogStream", "logs:PutLogEvents",
        "xray:PutTraceSegments", "xray:PutTelemetryRecords",
        "s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject",
        "cloudfront:CreateInvalidation"
      ]
      Resource = "*"
    }]
  })
}

# Ceiling for the run role itself.
resource "aws_iam_policy" "run_boundary" {
  #checkov:skip=CKV_AWS_355:A boundary is a ceiling, not a grant; the role policy scopes resources
  #checkov:skip=CKV_AWS_288:Ceiling only; the role policy grants S3 on this project's buckets alone
  #checkov:skip=CKV_AWS_289:Ceiling only; IAM writes are limited to devops-portfolio-* roles with the workload boundary
  #checkov:skip=CKV_AWS_290:Ceiling only; writes are scoped in the role policy
  #checkov:skip=CKV_AWS_286:Ceiling only; role creation needs the workload boundary and the denies block self-edits
  name = "${local.run_role}-boundary"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Ceiling"
        Effect = "Allow"
        Action = [
          "s3:*", "cloudfront:*", "cloudwatch:*", "sns:*", "acm:*", "route53:*", "dynamodb:*", "lambda:*", "logs:*", "apigateway:*", "sts:GetCallerIdentity",
          # IAM: only what managing the two workload roles needs
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:TagRole", "iam:UntagRole", "iam:ListRoleTags",
          "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:GetRolePolicy", "iam:DeleteRolePolicy", "iam:ListRolePolicies",
          "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:PassRole", "iam:GetOpenIDConnectProvider", "iam:ListOpenIDConnectProviders"
        ]
        Resource = "*"
      },
      {
        Sid    = "NoSelfOrBoundaryEdits"
        Effect = "Deny"
        Action = "iam:*"
        Resource = [
          "arn:aws:iam::${local.acct}:role/${local.run_role}",
          "arn:aws:iam::${local.acct}:policy/${local.run_role}-boundary",
          "arn:aws:iam::${local.acct}:policy/${local.prefix}-workload-boundary"
        ]
      },
      { Sid = "KeepBoundaries", Effect = "Deny", Action = "iam:DeleteRolePermissionsBoundary", Resource = "*" }
    ]
  })
}

# Only plan/apply runs of this one workspace can assume the role.
resource "aws_iam_role" "hcp" {
  name                 = local.run_role
  max_session_duration = 3600
  permissions_boundary = aws_iam_policy.run_boundary.arn
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.hcp.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = { "app.terraform.io:aud" = "aws.workload.identity" }
        StringLike   = { "app.terraform.io:sub" = "organization:${var.hcp_organization}:project:${var.hcp_project}:workspace:${var.hcp_workspace}:run_phase:*" }
      }
    }]
  })
}

# What the site's Terraform needs, scoped to this project's names where AWS allows it.
resource "aws_iam_role_policy" "hcp" {
  #checkov:skip=CKV_AWS_355:Only list/describe, acm:RequestCertificate and log-delivery actions use "*"; AWS doesn't support resource scoping for them
  #checkov:skip=CKV_AWS_290:Writes are scoped to this project's names or this account's CloudFront/ACM/Route 53 ARNs
  #checkov:skip=CKV_AWS_289:IAM writes only on devops-portfolio-* roles and only with the workload boundary attached
  #checkov:skip=CKV_AWS_286:Role creation requires the workload boundary; the run boundary denies self-edits and boundary removal
  name = "manage-devops-portfolio"
  role = aws_iam_role.hcp.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "SiteBucket", Effect = "Allow", Action = "s3:*", Resource = ["arn:aws:s3:::${local.prefix}-*", "arn:aws:s3:::${local.prefix}-*/*"] },
      { Sid = "CloudFront", Effect = "Allow", Action = "cloudfront:*", Resource = "arn:aws:cloudfront::${local.acct}:*" },
      { Sid = "CounterTable", Effect = "Allow", Action = "dynamodb:*", Resource = "arn:aws:dynamodb:us-east-1:${local.acct}:table/${local.prefix}-*" },
      { Sid = "CounterFunction", Effect = "Allow", Action = "lambda:*", Resource = "arn:aws:lambda:us-east-1:${local.acct}:function:${local.prefix}-*" },
      { Sid = "HttpApi", Effect = "Allow", Action = "apigateway:*", Resource = ["arn:aws:apigateway:us-east-1::/apis", "arn:aws:apigateway:us-east-1::/apis/*", "arn:aws:apigateway:us-east-1::/tags/*"] },
      {
        Sid = "LogGroups", Effect = "Allow", Action = "logs:*"
        Resource = [
          "arn:aws:logs:us-east-1:${local.acct}:log-group:/aws/lambda/${local.prefix}-*",
          "arn:aws:logs:us-east-1:${local.acct}:log-group:/aws/lambda/${local.prefix}-*:*",
          "arn:aws:logs:us-east-1:${local.acct}:log-group:/aws/apigateway/${local.prefix}-*",
          "arn:aws:logs:us-east-1:${local.acct}:log-group:/aws/apigateway/${local.prefix}-*:*"
        ]
      },
      {
        Sid       = "RolesOnlyWithBoundary", Effect = "Allow"
        Action    = ["iam:CreateRole", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:DeleteRolePolicy"]
        Resource  = local.roles
        Condition = { StringEquals = { "iam:PermissionsBoundary" = aws_iam_policy.workload_boundary.arn } }
      },
      {
        Sid      = "RolesManage", Effect = "Allow"
        Action   = ["iam:GetRole", "iam:DeleteRole", "iam:TagRole", "iam:UntagRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy", "iam:GetRolePolicy", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies", "iam:ListInstanceProfilesForRole", "iam:ListRoleTags"]
        Resource = local.roles
      },
      {
        Sid       = "PassCounterRole", Effect = "Allow", Action = "iam:PassRole"
        Resource  = "arn:aws:iam::${local.acct}:role/${local.prefix}-visits-lambda"
        Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
      },
      { Sid = "GithubOidcRead", Effect = "Allow", Action = "iam:GetOpenIDConnectProvider", Resource = "arn:aws:iam::${local.acct}:oidc-provider/token.actions.githubusercontent.com" },
      { Sid = "Alarms", Effect = "Allow", Action = ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:ListTagsForResource", "cloudwatch:TagResource", "cloudwatch:UntagResource"], Resource = "arn:aws:cloudwatch:us-east-1:${local.acct}:alarm:${local.prefix}-*" },
      { Sid = "AlertTopic", Effect = "Allow", Action = "sns:*", Resource = "arn:aws:sns:us-east-1:${local.acct}:${local.prefix}-*" },
      { Sid = "CertManage", Effect = "Allow", Action = ["acm:DescribeCertificate", "acm:DeleteCertificate", "acm:AddTagsToCertificate", "acm:ListTagsForCertificate", "acm:RemoveTagsFromCertificate"], Resource = "arn:aws:acm:us-east-1:${local.acct}:certificate/*" },
      { Sid = "DnsRecords", Effect = "Allow", Action = ["route53:GetHostedZone", "route53:ListResourceRecordSets", "route53:ChangeResourceRecordSets", "route53:ListTagsForResource"], Resource = "arn:aws:route53:::hostedzone/*" },
      {
        Sid = "UnscopableReads", Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms", "acm:RequestCertificate", "acm:ListCertificates", "route53:ListHostedZones", "route53:GetChange",
          "cloudfront:ListCachePolicies", "cloudfront:GetCachePolicy", "cloudfront:ListResponseHeadersPolicies", "cloudfront:GetResponseHeadersPolicy",
          "cloudfront:ListOriginRequestPolicies", "cloudfront:GetOriginRequestPolicy",
          "iam:ListOpenIDConnectProviders", "logs:DescribeLogGroups",
          "logs:CreateLogDelivery", "logs:GetLogDelivery", "logs:UpdateLogDelivery", "logs:DeleteLogDelivery", "logs:ListLogDeliveries",
          "logs:PutResourcePolicy", "logs:DescribeResourcePolicies", "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

output "hcp_run_role_arn" {
  value       = aws_iam_role.hcp.arn
  description = "Set as workspace env var TFC_AWS_RUN_ROLE_ARN (with TFC_AWS_PROVIDER_AUTH=true)"
}
