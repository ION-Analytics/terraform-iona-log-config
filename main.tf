terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

locals{
  default_log_config = {
    logDriver = "awsfirelens",
    options = {
        Name = "datadog",
        apiKey = var.datadog_api_key,
        dd_service = var.service_name,
        dd_source = var.sourcetype,
        dd_tags = var.tags,
        TLS = "on",
        provider = "ecs"
    }
  }
  default_firelens_config = {
    type = "fluentbit"
    options = {
      enable-ecs-log-metadata = "true"
      config-file-type =  "s3",
      config-file-value = aws_s3_object.fluentbit_config.arn
    }
  }
}

resource "aws_s3_object" "fluentbit_config" {
  bucket = data.aws_s3_bucket.fluentbit.id
  key    = "${var.service_name}-${var.ecs_cluster}-fluentbit.conf"
  content = local.fluentbit_config
}


locals{
  default_fluentbit_config = <<-EOF
[FILTER]
    Name                  record_modifier
    Match                 *
    Record ecs_service_name ${var.service_name}
    Record service ${var.service_name}
    Record host ${var.ecs_cluster}

[FILTER]
    Name    grep
    Match   *
    Exclude log ELB-HealthChecker/2.0

[OUTPUT]
    Name firehose
    Match *
    delivery_stream ArchiveFirehoseStream
    region ${data.aws_region.current.name}

EOF
}

locals{
    fluentbit_config = join("\n", [local.default_fluentbit_config, var.custom_fluentbit_config])
}

output "file_arn" {
    value = aws_s3_object.fluentbit_config.arn
}


output "log_config" {
    value = local.default_log_config
}

output "firelens_config" {
    value = local.default_firelens_config
}
