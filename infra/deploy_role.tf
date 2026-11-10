# Keyless deploys: GitHub Actions on main assumes this role via OIDC.
# It can only sync this bucket and invalidate this distribution; it cannot change infrastructure.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com" # created once by aws-secure-landing-zone
}

locals {
  gh_sub = "repo:${split("/", var.github_repo)[0]}@${var.github_owner_id}/${split("/", var.github_repo)[1]}@${var.github_repo_id}"
}

resource "aws_iam_role" "deploy" {
  name                 = "${local.name}-github-deploy"
  permissions_boundary = local.workload_boundary
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = data.aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "${local.gh_sub}:ref:refs/heads/main"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  name = "sync-site-and-invalidate"
  role = aws_iam_role.deploy.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "s3:ListBucket", Resource = aws_s3_bucket.site.arn },
      { Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject"], Resource = "${aws_s3_bucket.site.arn}/*" },
      { Effect = "Allow", Action = "cloudfront:CreateInvalidation", Resource = aws_cloudfront_distribution.site.arn }
    ]
  })
}
