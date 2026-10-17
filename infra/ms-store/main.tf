resource "aws_s3_bucket" "packages" {
  bucket = var.bucket_name
  tags   = { Name = var.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "packages" {
  bucket                  = aws_s3_bucket.packages.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "packages" {
  bucket = aws_s3_bucket.packages.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "packages" {
  bucket = aws_s3_bucket.packages.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "packages" {
  name                              = "prelis-ms-store-oac"
  description                       = "Private S3 origin for Prelis MSI packages"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "packages" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = var.public_domain == null ? [] : [var.public_domain]
  price_class     = "PriceClass_All"
  tags            = { Name = "prelis-ms-store-cloudfront" }

  origin {
    domain_name              = aws_s3_bucket.packages.bucket_regional_domain_name
    origin_id                = "s3-prelis-ms-store"
    origin_access_control_id = aws_cloudfront_origin_access_control.packages.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-prelis-ms-store"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn            = var.public_domain == null ? null : var.acm_certificate_arn
    cloudfront_default_certificate = var.public_domain == null
    ssl_support_method             = var.public_domain == null ? null : "sni-only"
    minimum_protocol_version       = var.public_domain == null ? null : "TLSv1.2_2021"
  }

  lifecycle {
    precondition {
      condition     = var.public_domain == null || var.acm_certificate_arn != null
      error_message = "A custom public_domain requires acm_certificate_arn."
    }
  }
}

resource "aws_s3_bucket_policy" "packages" {
  bucket = aws_s3_bucket.packages.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.packages.arn}/windows/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.packages.arn } }
      },
      {
        Sid       = "RequireCreateOnlyUploads"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.packages.arn}/windows/*"
        Condition = {
          Null = { "s3:if-none-match" = "true" }
          Bool = { "s3:ObjectCreationOperation" = "true" }
        }
      },
      {
        Sid       = "DenyPackageDeletion"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteObject", "s3:DeleteObjectVersion"]
        Resource  = "${aws_s3_bucket.packages.arn}/windows/*"
      }
    ]
  })
  depends_on = [aws_s3_bucket_public_access_block.packages]
}

resource "aws_route53_record" "packages_ipv4" {
  count   = var.public_domain != null && var.route53_zone_id != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.public_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.packages.domain_name
    zone_id                = aws_cloudfront_distribution.packages.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "packages_ipv6" {
  count   = var.public_domain != null && var.route53_zone_id != null ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.public_domain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.packages.domain_name
    zone_id                = aws_cloudfront_distribution.packages.hosted_zone_id
    evaluate_target_health = false
  }
}

output "bucket_name" {
  value = aws_s3_bucket.packages.bucket
}

output "aws_region" {
  value = var.aws_region
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.packages.id
}

output "package_base_url" {
  value = "https://${var.public_domain == null ? aws_cloudfront_distribution.packages.domain_name : var.public_domain}/windows/"
}
