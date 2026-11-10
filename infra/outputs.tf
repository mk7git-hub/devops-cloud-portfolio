output "site_url" {
  value = local.use_domain ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.site.domain_name}"
}
output "distribution_id" { value = aws_cloudfront_distribution.site.id }
output "bucket" { value = aws_s3_bucket.site.bucket }
output "deploy_role_arn" { value = aws_iam_role.deploy.arn }
output "alarm_names" { value = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name] }
