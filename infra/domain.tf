# Optional custom domain: set domain_name to a domain with a Route 53 hosted zone in this account.
data "aws_route53_zone" "site" {
  count = local.use_domain ? 1 : 0
  name  = var.domain_name
}

resource "aws_acm_certificate" "site" {
  count                     = local.use_domain ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validation" {
  for_each = local.use_domain ? { for o in aws_acm_certificate.site[0].domain_validation_options : o.domain_name => o } : {}
  zone_id  = data.aws_route53_zone.site[0].zone_id
  name     = each.value.resource_record_name
  type     = each.value.resource_record_type
  records  = [each.value.resource_record_value]
  ttl      = 60
}

resource "aws_acm_certificate_validation" "site" {
  count                   = local.use_domain ? 1 : 0
  certificate_arn         = aws_acm_certificate.site[0].arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

resource "aws_route53_record" "alias" {
  for_each = local.use_domain ? toset([var.domain_name, "www.${var.domain_name}"]) : toset([])
  zone_id  = data.aws_route53_zone.site[0].zone_id
  name     = each.value
  type     = "A"
  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
