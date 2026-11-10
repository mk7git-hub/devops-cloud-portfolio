# Visitor counter: API Gateway (HTTP API) -> Lambda -> DynamoDB
resource "aws_dynamodb_table" "visits" {
  #checkov:skip=CKV_AWS_119:Table holds one public number; AWS-owned key encryption is enough and a CMK costs $1/month

  name         = "${local.name}-visits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
  point_in_time_recovery { enabled = true }
  server_side_encryption { enabled = true }
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../backend/visits.py"
  output_path = "${path.module}/.build/visits.zip"
}

resource "aws_iam_role" "lambda" {
  name                 = "${local.name}-visits-lambda"
  permissions_boundary = local.workload_boundary
  assume_role_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }]
  })
}

resource "aws_iam_role_policy" "lambda" {
  name = "counter-only"
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:UpdateItem", "dynamodb:GetItem"], Resource = aws_dynamodb_table.visits.arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.lambda.arn}:*" },
      { Effect = "Allow", Action = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"], Resource = "*" }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  #checkov:skip=CKV_AWS_338:14-day retention; the counter holds no security-relevant data and logs cost money
  #checkov:skip=CKV_AWS_158:Default CloudWatch encryption is enough for request logs with no PII

  name              = "/aws/lambda/${local.name}-visits"
  retention_in_days = 14
}

resource "aws_lambda_function" "visits" {
  #checkov:skip=CKV_AWS_115:Reserved concurrency is a variable; new accounts cannot reserve any (limit 10, 10 must stay unreserved)
  #checkov:skip=CKV_AWS_116:A DLQ adds nothing for a synchronous API call; failures return 5xx to the browser
  #checkov:skip=CKV_AWS_117:No VPC needed; the function only calls DynamoDB over the AWS API
  #checkov:skip=CKV_AWS_173:No secrets in environment variables, only a table name
  #checkov:skip=CKV_AWS_272:Code signing is out of scope for a single-file portfolio function

  function_name                  = "${local.name}-visits"
  role                           = aws_iam_role.lambda.arn
  runtime                        = "python3.12"
  handler                        = "visits.handler"
  filename                       = data.archive_file.lambda.output_path
  source_code_hash               = data.archive_file.lambda.output_base64sha256
  timeout                        = 5
  memory_size                    = 128
  reserved_concurrent_executions = var.reserved_concurrency
  environment {
    variables = { TABLE_NAME = aws_dynamodb_table.visits.name }
  }
  tracing_config { mode = "Active" }
  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_apigatewayv2_api" "api" {
  name          = "${local.name}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "visits" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.visits.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "visits" {
  #checkov:skip=CKV_AWS_309:Public by design (anonymous page-view counter); throttling and Lambda limits bound abuse

  for_each  = toset(["GET /api/visits", "POST /api/visits"])
  api_id    = aws_apigatewayv2_api.api.id
  route_key = each.value
  target    = "integrations/${aws_apigatewayv2_integration.visits.id}"
}

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_338:14-day retention for access logs of a public counter
  #checkov:skip=CKV_AWS_158:Default CloudWatch encryption is enough for request logs with no PII

  name              = "/aws/apigateway/${local.name}-api"
  retention_in_days = 14
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
  default_route_settings {
    throttling_burst_limit = var.api_rate_limit * 2
    throttling_rate_limit  = var.api_rate_limit
  }
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format          = jsonencode({ requestId = "$context.requestId", ip = "$context.identity.sourceIp", route = "$context.routeKey", status = "$context.status", latency = "$context.responseLatency" })
  }
}

resource "aws_lambda_permission" "api" {
  statement_id  = "AllowHttpApi"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visits.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/api/visits"
}
