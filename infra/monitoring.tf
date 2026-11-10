# Alarms for the edge, the API and the function, all to one SNS topic (alarm and recovery).
# CloudFront publishes metrics to us-east-1 under Region=Global.
resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:Alert messages contain only metric names and thresholds; default encryption is enough
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

locals {
  cdn_dims = { DistributionId = aws_cloudfront_distribution.site.id, Region = "Global" }
  alarms = {
    "requests-spike" = { ns = "AWS/CloudFront", metric = "Requests", stat = "Sum", threshold = var.request_spike_threshold, dims = local.cdn_dims, why = "Abnormal traffic (bot or scrape)" }
    "5xx-rate"       = { ns = "AWS/CloudFront", metric = "5xxErrorRate", stat = "Average", threshold = 1, dims = local.cdn_dims, why = "Origin or CloudFront errors" }
    "4xx-rate"       = { ns = "AWS/CloudFront", metric = "4xxErrorRate", stat = "Average", threshold = 5, dims = local.cdn_dims, why = "Broken links or missing pages" }
    "api-5xx"        = { ns = "AWS/ApiGateway", metric = "5xx", stat = "Sum", threshold = 5, dims = { ApiId = aws_apigatewayv2_api.api.id, Stage = "$default" }, why = "Counter API failing" }
    "lambda-errors"  = { ns = "AWS/Lambda", metric = "Errors", stat = "Sum", threshold = 5, dims = { FunctionName = aws_lambda_function.visits.function_name }, why = "Counter function erroring" }
  }
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each            = local.alarms
  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.why
  namespace           = each.value.ns
  metric_name         = each.value.metric
  statistic           = each.value.stat
  period              = 300
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = each.value.dims
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}
