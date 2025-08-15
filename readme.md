# Terraform-IONA-Log-Config module

This module is intended to be used with the ION-Analytics/ecs-service/iona module and will simplify the default firelens config.

Example call:

```
module "ecs_service" {

  source = "ION-Analytics/ecs-service/iona"
  version = ">= 3.2.0"

  providers = {
    aws = aws.cluster_provider
  }

...

  firelens_configuration = module.log_config.firelens_config
  log_configuration = module.log_config.log_config

}
```

## Useful variables

service_name: Name of the service. Used to tag the datadog output and name the bucket for the extended config. Also added to the Fluent-bit tagging

datadog_api_key: Used to connect directly to datadog in Firelens

sourcetype: The name of the logfile / sourcetype. Used in the tagging.

tags: used in the dd_tags option of the firelens driver. A string of key:value tags separated by whitespace

ecs_cluster: The name of the cluster. Used to tag the datadog output and name the bucket for the extended config. Also added to the Fluent-bit tagging

custom_fluentbit_config: HEREDOC with custom fluentbit options. INDENTATION LEVELS ARE IMPORTANT. Here's a sample for reference, but DO NOT USE THIS SAMPLE.

```
   custom_fluentbit_config = <<EOF
[OUTPUT]
    Name firehose
    Match *
    delivery_stream ArchiveFirehoseStream
    region us-west-2
EOF
```

For more information on Fluentbit configurations, see https://docs.fluentbit.io/manual/data-pipeline/pipeline-monitoring

