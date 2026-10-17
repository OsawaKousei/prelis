resource "aws_s3_bucket" "apt" {
  bucket = var.bucket_name
  tags   = { Name = var.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "apt" {
  bucket                  = aws_s3_bucket.apt.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "apt" {
  bucket = aws_s3_bucket.apt.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "apt" {
  bucket = aws_s3_bucket.apt.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "apt" {
  bucket = aws_s3_bucket.apt.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "apt" {
  name                              = "prelis-apt-repo-oac"
  description                       = "Private S3 origin for Prelis APT packages"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "apt" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [var.public_domain]
  price_class     = "PriceClass_All"
  tags            = { Name = "prelis-apt-repo-cloudfront" }

  origin {
    domain_name              = aws_s3_bucket.apt.bucket_regional_domain_name
    origin_id                = "s3-prelis-apt-repo"
    origin_access_control_id = aws_cloudfront_origin_access_control.apt.id
  }

  # The root cache behavior serves the public key for one hour.
  default_cache_behavior {
    target_origin_id       = "s3-prelis-apt-repo"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 3600

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }
  }

  # Release and Packages must be fetched fresh together on each apt update.
  ordered_cache_behavior {
    path_pattern           = "/apt/dists/*"
    target_origin_id       = "s3-prelis-apt-repo"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    cache_policy_id        = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # AWS managed CachingDisabled
  }

  # Versioned .deb files remain at the same path and may be cached for a year.
  ordered_cache_behavior {
    path_pattern           = "/apt/pool/*"
    target_origin_id       = "s3-prelis-apt-repo"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = false
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed CachingOptimized
  }

  custom_error_response {
    error_code            = 403
    error_caching_min_ttl = 0
  }

  custom_error_response {
    error_code            = 404
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_s3_bucket_policy" "apt" {
  bucket = aws_s3_bucket.apt.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontReadPrelisAPT"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.apt.arn}/apt/*"
      Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.apt.arn } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.apt]
}

resource "aws_route53_record" "apt_ipv4" {
  zone_id = var.route53_zone_id
  name    = var.public_domain
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.apt.domain_name
    zone_id                = aws_cloudfront_distribution.apt.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "apt_ipv6" {
  zone_id = var.route53_zone_id
  name    = var.public_domain
  type    = "AAAA"
  alias {
    name                   = aws_cloudfront_distribution.apt.domain_name
    zone_id                = aws_cloudfront_distribution.apt.hosted_zone_id
    evaluate_target_health = false
  }
}

output "bucket_name" {
  value = aws_s3_bucket.apt.bucket
}

output "aws_region" {
  value = var.aws_region
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.apt.id
}

output "apt_base_url" {
  value = "https://${var.public_domain}/apt/"
}
