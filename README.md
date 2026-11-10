# DevOps Cloud Portfolio: serverless on AWS, deployed with no stored keys

[![ci-deploy](https://github.com/mk7git-hub/devops-cloud-portfolio/actions/workflows/ci-deploy.yml/badge.svg)](https://github.com/mk7git-hub/devops-cloud-portfolio/actions/workflows/ci-deploy.yml)

My portfolio site, built the way I'd build a production service: a private S3 origin behind CloudFront, a live visitor counter (API Gateway → Lambda → DynamoDB), every resource in Terraform, and GitHub Actions deploying through OIDC with no AWS keys anywhere.

**Live site:** `<CloudFront URL after first deploy>`  ·  **Sister version:** [devops-cloud-portfolio-v2](https://github.com/mk7git-hub/devops-cloud-portfolio-v2) (HCP Terraform + monitoring)

## Architecture

```
Browser
  └── CloudFront (HTTPS, Origin Access Control, managed security headers)
        ├── /*      → S3 (private, versioned, SSE, TLS-only bucket policy)
        └── /api/*  → API Gateway HTTP API (throttled)
                        └── Lambda (Python 3.12, least privilege) → DynamoDB (atomic counter, PITR)

GitHub push to main ──OIDC──▶ deploy role (sync this bucket + invalidate this distribution, nothing else)
```

## Design decisions

| Decision | Why | Trade-off |
| --- | --- | --- |
| API behind CloudFront at `/api/*` | Same origin as the site: no CORS, no API URL in the page, one TLS endpoint | API Gateway's own URL is still reachable; throttling and Lambda limits bound abuse |
| Atomic `ADD` in DynamoDB | Two visitors at once never lose a count, no read-then-write race | None |
| OIDC deploy role scoped to `S3 sync + CreateInvalidation` | A leaked workflow can't change infrastructure or read anything else | Infra changes are applied by me with `terraform apply`, not by CI |
| Trust policy pinned to `repo:owner@id/repo@id:ref:refs/heads/main` | GitHub's immutable-ID subject: a renamed or recreated repo can't inherit the role | Needs the numeric owner and repo IDs as variables |
| HTML cached 5 min, assets 1 day | New deploys are visible fast while assets stay cheap | Invalidation on every deploy (first 1,000 paths/month are free) |
| Reserved concurrency as a variable, off by default | New accounts have a concurrency limit of 10 and AWS keeps 10 unreserved, so reserving fails | Turn it on once the limit is raised |
| Domain/ACM/Route 53 code included but switched off | Free CloudFront URL now; one variable adds a custom domain later | None |

Checkov: 60 passed, 0 failed, 24 documented exceptions (each `#checkov:skip` in the code says why, mostly cost decisions for a public site).

## Repo layout

```
site/            index.html, 404.html, assets/ (CSS, JS: filter, theme toggle, counter)
backend/         visits.py: the counter Lambda
tests/           pytest for the Lambda (atomic increment, read-only GET, 405, no-cache)
infra/           Terraform: site.tf, cdn.tf, api.tf, deploy_role.tf, domain.tf (optional)
.github/         ci-deploy.yml: test → fmt/validate/tflint/checkov → deploy on main
```

## Deploy it

Prerequisites: the GitHub OIDC provider and S3 state backend from [aws-secure-landing-zone](https://github.com/mk7git-hub/aws-secure-landing-zone), AWS CLI signed in.

```bash
cd infra
cp backend.hcl.example backend.hcl            # fill in your state bucket
cp terraform.tfvars.example terraform.tfvars  # owner, repo, GitHub IDs
terraform init -backend-config=backend.hcl
terraform apply
```

Then set four repository **variables** (Settings → Secrets and variables → Actions → Variables; none are secrets) from `terraform output`: `AWS_DEPLOY_ROLE_ARN`, `SITE_BUCKET`, `CF_DISTRIBUTION_ID`, `SITE_URL`. Every push to `main` now tests and deploys.

## Cost

Low-traffic estimate: S3 cents, CloudFront within the free tier, API Gateway/Lambda/DynamoDB within the free tier for a portfolio's traffic. Roughly **$0–1 per month**. `terraform destroy` removes everything.

## Evidence

`docs/img/` (added after the first deploy): the pipeline run, the live site, and the counter incrementing.

## Credits

Pattern inspired by the [Cloud Resume Challenge](https://cloudresumechallenge.dev/) by Forrest Brazeal.
