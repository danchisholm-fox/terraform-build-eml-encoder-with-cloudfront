###### CloudFront in front of MediaPackage (EMP) for playback

locals {
  # MediaPackage HLS endpoint URL created via CloudFormation in mediapackage.tf
  emp_hls_url       = aws_cloudformation_stack.emp_hls_endpoint.outputs["EndpointUrl"]
  emp_no_scheme     = replace(local.emp_hls_url, "https://", "")
  emp_url_parts     = split("/", local.emp_no_scheme)
  emp_domain        = local.emp_url_parts[0]

  # Origin path is everything except the domain and the final manifest file
  emp_path_parts    = slice(local.emp_url_parts, 1, length(local.emp_url_parts) - 1)
  emp_origin_path   = join("/", concat([""], local.emp_path_parts))

  # Last segment should be the manifest (e.g., index.m3u8)
  emp_manifest_file = local.emp_url_parts[length(local.emp_url_parts) - 1]
}

resource "aws_cloudfront_distribution" "emp_front" {
  enabled     = true
  price_class = var.cf_price_class
  comment     = "${var.project_name} CloudFront in front of MediaPackage HLS"

  origin {
    domain_name = local.emp_domain
    origin_id   = "emp-origin"
    origin_path = local.emp_origin_path

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "emp-origin"
    viewer_protocol_policy = "redirect-to-https"
    trusted_key_groups     = []


    forwarded_values {
      query_string = true
      cookies { forward = "none" }
    }

    # Live HLS is time-sensitive; keep TTLs small to align with segment durations
    min_ttl     = 0
    default_ttl = 6
    max_ttl     = 60
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

output "cloudfront_emp_domain_name" {
  description = "CloudFront domain name for EMP playback"
  value       = aws_cloudfront_distribution.emp_front.domain_name
}

output "cloudfront_emp_playback_url" {
  description = "Convenience URL to play via CloudFront (default root manifest)"
  value       = "https://${aws_cloudfront_distribution.emp_front.domain_name}/${local.emp_manifest_file}"
}

