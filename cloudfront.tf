# CloudFront with OAC to serve slate from S3 privately

data "aws_s3_bucket" "content" {
  bucket = var.content_bucket_name
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${var.project_name} content"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_public_key" "pk" {
  name        = "${var.project_name}-pk"
  encoded_key = tls_private_key.cf_signer.public_key_pem
  comment     = "Public key for signed URLs"
}

resource "aws_cloudfront_key_group" "kg" {
  name  = "${var.project_name}-kg"
  items = [aws_cloudfront_public_key.pk.id]
}

resource "tls_private_key" "cf_signer" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_cloudfront_distribution" "dist" {
  enabled             = true
  price_class         = var.cf_price_class
  comment             = "${var.project_name} slate distribution"

  origin {
    domain_name              = data.aws_s3_bucket.content.bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies { forward = "none" }
    }

    # Default behavior requires signed URLs via key group
    trusted_key_groups = [aws_cloudfront_key_group.kg.id]
    min_ttl            = 0
    default_ttl        = 86400
    max_ttl            = 31536000
  }

  # Allow unsigned access just for slates/* so MediaLive can pull without signing
  ordered_cache_behavior {
    path_pattern           = "slates/*"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-origin"
    viewer_protocol_policy = "redirect-to-https"

    forwarded_values {
      query_string = true
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

data "aws_iam_policy_document" "s3_oac_policy" {
  statement {
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "${data.aws_s3_bucket.content.arn}/${var.content_key_path}",
      "${data.aws_s3_bucket.content.arn}/${split("/", var.content_key_path)[0]}/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.dist.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "oac" {
  bucket = data.aws_s3_bucket.content.id
  policy = data.aws_iam_policy_document.s3_oac_policy.json
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.dist.domain_name
}

output "cloudfront_signer_private_key_pem" {
  description = "Private key PEM to sign URLs (store securely)"
  value       = tls_private_key.cf_signer.private_key_pem
  sensitive   = true
}

output "cloudfront_public_key_id" {
  description = "Public key ID used in CloudFront signed URLs (Key-Pair-Id)"
  value       = aws_cloudfront_public_key.pk.id
}

output "cloudfront_key_group_id" {
  description = "CloudFront Key Group ID (for reference)"
  value       = aws_cloudfront_key_group.kg.id
}

# Write private key to local file (0600)
resource "local_file" "cf_private_key" {
  filename = "${path.module}/cf_private_key.pem"
  content  = tls_private_key.cf_signer.private_key_pem
  file_permission = "0600"
}

