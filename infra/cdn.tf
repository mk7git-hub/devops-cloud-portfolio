data "aws_cloudfront_cache_policy" "optimized" { name = "Managed-CachingOptimized" }
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_origin_request_policy" "api" { name = "Managed-AllViewerExceptHostHeader" }
data "aws_cloudfront_response_headers_policy" "security" { name = "Managed-SecurityHeadersPolicy" }

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "site" {
  #checkov:skip=CKV_AWS_68:WAF costs more than the whole site; API throttling and Lambda limits bound abuse instead
  #checkov:skip=CKV_AWS_86:Access logging off to stay near-free; CloudWatch metrics cover traffic
  #checkov:skip=CKV_AWS_310:Origin failover needs a second bucket; not worth it for a portfolio
  #checkov:skip=CKV_AWS_374:No geo restriction; recruiters can be anywhere
  #checkov:skip=CKV2_AWS_47:Log4j WAF rule not applicable (no WAF, no Java)
  #checkov:skip=CKV2_AWS_32:Response headers policy is set on every behavior via the managed SecurityHeadersPolicy
  #checkov:skip=CKV2_AWS_42:Custom certificate only when domain_name is set; default certificate otherwise
  #checkov:skip=CKV_AWS_174:TLS 1.2 minimum is enforced whenever a custom certificate is used

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "DevOps Cloud Portfolio"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = local.use_domain ? [var.domain_name, "www.${var.domain_name}"] : []

  origin {
    origin_id                = "s3-site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id   = "api"
    domain_name = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  # Same-origin API: the browser calls /api/visits on the site's own domain, so no CORS.
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = "api"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.api.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  custom_error_response {
    error_code         = 403
    response_code      = 404
    response_page_path = "/404.html"
  }
  custom_error_response {
    error_code         = 404
    response_code      = 404
    response_page_path = "/404.html"
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_domain
    acm_certificate_arn            = local.use_domain ? aws_acm_certificate_validation.site[0].certificate_arn : null
    ssl_support_method             = local.use_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_domain ? "TLSv1.2_2021" : null
  }
}
