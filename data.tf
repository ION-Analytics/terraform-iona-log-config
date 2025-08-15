data "aws_region" "current" {}

data "aws_s3_bucket" "fluentbit" {
  bucket = var.platform_config["firelens_bucket"]
}
