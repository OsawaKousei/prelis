variable "aws_region" {
  description = "AWS region for the private web assets bucket"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "Optional AWS shared config profile; null uses the standard credential chain"
  type        = string
  default     = null
  nullable    = true
}

variable "tags" {
  description = "Tags applied to resources"
  type        = map(string)
  default     = {}
}

variable "bucket_name" {
  description = "Globally unique private S3 bucket name for the web frontend"
  type        = string
}

variable "public_domain" {
  description = "Public domain for the web frontend"
  type        = string
  default     = "app-prelis.prj.kupac.co.jp"
}

variable "acm_certificate_arn" {
  description = "Issued ACM certificate ARN in us-east-1 covering public_domain"
  type        = string

  validation {
    condition     = can(regex("^arn:aws:acm:us-east-1:[0-9]{12}:certificate/[0-9a-f-]+$", var.acm_certificate_arn))
    error_message = "CloudFront requires an ACM certificate ARN from us-east-1."
  }
}

variable "route53_zone_id" {
  description = "Route 53 public hosted zone ID for the A and AAAA alias records"
  type        = string
}
