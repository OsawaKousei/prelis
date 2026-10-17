#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
infra_dir="$repo_root/infra/web-frontend"
dist_dir="$repo_root/apps/web/dist"

if [[ $# -ne 0 ]]; then
  echo "Usage: $0" >&2
  exit 2
fi

export AWS_PROFILE="${AWS_PROFILE:-kupacllc}"

npm --prefix "$repo_root" run build:web

bucket="$(terraform -chdir="$infra_dir" output -raw website_bucket_name)"
region="$(terraform -chdir="$infra_dir" output -raw aws_region)"
distribution_id="$(terraform -chdir="$infra_dir" output -raw cloudfront_distribution_id)"
public_url="$(terraform -chdir="$infra_dir" output -raw public_url)"

# Keep previous hashed assets so open tabs can finish loading an older build.
aws s3 sync "$dist_dir/assets/" "s3://$bucket/assets/" \
  --region "$region" \
  --cache-control 'public, max-age=31536000, immutable'
aws s3 sync "$dist_dir/" "s3://$bucket/" \
  --region "$region" \
  --exclude 'assets/*' --exclude 'index.html' \
  --cache-control 'public, max-age=300'
aws s3 cp "$dist_dir/index.html" "s3://$bucket/index.html" \
  --region "$region" \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache, max-age=0, must-revalidate'

invalidation_id="$(aws cloudfront create-invalidation \
  --distribution-id "$distribution_id" --paths '/*' \
  --query 'Invalidation.Id' --output text)"

echo "Published: $public_url"
echo "CloudFront invalidation: $invalidation_id"
