# A preface about logging from containers

With normal EC2 instances it's common to have logs scattered around the file system in several different formats. In the past we've used splunk to collect these files and parse them into useful data.

With containers logs are generally collected by emitting them to STDOUT and STDERR. This can be an issue if your log lines are not all emitted in the same format (think web access logs vs java stack traces)

As such it's best practice to format your log output in the following ways:
* JSON format
* No line breaks

JSON format allows the log entry ot parsed into a series of key/values or even more complex data structures that would be hard to encapsulate on a single line. Most log formatters have a json option available:
* Log4J2: https://logging.apache.org/log4j/2.x/manual/json-template-layout.html
* Here's a sampling of Ruby formatters: https://www.highlight.io/blog/5-best-ruby-logging-libraries
* Python: https://pypi.org/project/python-json-logger/
* Here's a general article that talks about the benefits of logging via JSON: https://betterstack.com/community/guides/logging/json-logging/

No line breaks is especially important for things like Stack Traces from Java. Because docker has no way of knowing if a new line is a continuation of the previous event or not, it can be difficult to turn a 140-line stack trace into a single event. Especially if multiple threads are writing at the same time. Your log formatter should have a way of replacing or removing end-of-line characters:

* Log4J2: Use the 'compact=true' flag in your JSON formatter: https://logging.apache.org/log4j/2.x/manual/layouts.html#JSONLayout
* Ruby: https://stackoverflow.com/questions/13311694/how-to-format-ruby-exception-with-backtrace-into-a-string
* Python: I _think_ this is handled automatically by the python json logger?

# Terraform-IONA-Log-Config module

This module is intended to be called from a ECS service repo that wants to log through Firelens/Fluent-bit into Datadog.

Such a service should be using the https://registry.terraform.io/modules/ION-Analytics/ecs-service/iona/latest module and would include the following into the configuration:

```
  firelens_configuration = module.log-config.firelens_config
  log_configuration = module.log-config.log_config
```
This block sets up the fluent-bit sidecar and tells our service to send logs to that sidecar. Without this block logging is only done to cloudwatch.

** This module requires the addition of a "firelens_bucket" key/value to your platform_config **

That key is used to define where the additional fluentbit configuration object will be stored

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

When adding the module to your service, it should be called from your terraform like so:

```
data "aws_secretsmanager_secret" "datadog_api_key" {
  name     = "datadog_api_key"
}

data "aws_secretsmanager_secret_version" "datadog_api_key" {
  secret_id = data.aws_secretsmanager_secret.datadog_api_key.id
}

module "log-config" {
  source  = "ION-Analytics/log-config/iona"
  version = ">=1.0.2"

  providers = {
    aws = aws.cluster_provider
  }
  platform_config = module.platform_config.config
  service_name = var.service_name
  ecs_cluster = local.ecs_cluster
  tags = "project:${var.service_name}"
  sourcetype = "syslog"
  datadog_api_key = jsondecode(data.aws_secretsmanager_secret_version.datadog_api_key.secret_string)["datadog_api_key"]
}
```

The two data resources allow us to look up the datadog API key so that we can send our logs directly to Datadog from the firelens sidecar container

## Useful variables
* platform_config: The platform config module for our AWS account / datacenter. This provides a number of useful pointers to external resources (see https://github.com/mergermarket/capplatformbsg-platform-config for examples)
* service_name: Name of the service. Used to tag the datadog output and name the bucket for the extended config. Also added to the Fluent-bit tagging
* datadog_api_key: Used to connect directly to datadog in Firelens
* sourcetype: The name of the logfile / sourcetype. Used in the tagging.
* tags: used in the dd_tags option of the firelens driver. A string of key:value tags separated by whitespace
* ecs_cluster: The name of the cluster. Used to tag the datadog output and name the bucket for the extended config. Also added to the Fluent-bit tagging
* custom_fluentbit_config: HEREDOC with custom fluentbit options. INDENTATION LEVELS ARE IMPORTANT. See below for examples

# Fluent-bit logs

The default Fluent-bit config (provided by the default AWS ECS task definition) looks like this:

```
[INPUT]
    Name forward
    Mem_Buf_Limit 25MB
    unix_path /var/run/fluent.sock

[INPUT]
    Name forward
    Listen 0.0.0.0
    Port 24224

[INPUT]
    Name tcp
    Tag firelens-healthcheck
    Listen 127.0.0.1
    Port 8877

[FILTER]
    Name record_modifier
    Match *
    Record ec2_instance_id i-0d1a7bebd0e42bc04
    Record ecs_cluster or1-test
    Record ecs_task_arn arn:aws:ecs:us-west-2:254076036999:task/or1-test/a87638ce0fa0408ba98d11d70dbc66b8
    Record ecs_task_definition or1-test-cdflow-log-testing:37

[OUTPUT]
    Name null
    Match firelens-healthcheck

[OUTPUT]
    Name firehose
    Match cdflow-log-testing-firelens*
    delivery_stream DatadogFirehoseStream
    region us-west-2
```

Our log-config module adds some extra directives in an external configuration file, so this gets added to the default config:
```
@INCLUDE /fluent-bit/etc/external.conf
```

Specifically, we add this (variables would be replaced by their values):
```
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
```

In order this configuration does the following:
* Adds the ecs_service_name, service, and host tags to the event
* Drops any event that contains the string "ELB-HealthChecker/2.0" (this is the user-agent for the AWS ELB health check)
* Archives a copy of the event to the Archive Firehose Stream in the current AWS account/region


If we wanted to add more to this external configuration, we would create a local variable like so (DO NOT USE THIS EXAMPLE WITHOUT UNDERSTANDING HOW THE FILTER WORKS):
```
locals{
  custom_fluentbit_config = <<-EOF
[FILTER]
    name                  multiline
    match                 *
    multiline.key_content log
    multiline.parser      go
EOF
}
```
And pass that to the log-config module like this:
```
custom_fluentbit_config = local.custom_fluentbit_config
```

And the file is uploaded to S3 by this bit:
```
data "aws_s3_bucket" "fluentbit" {
  provider = aws.cluster_provider
  bucket = module.platform_config.config["firelens_bucket"]
}

resource "aws_s3_object" "fluentbit_config" {
  provider = aws.cluster_provider
  bucket = data.aws_s3_bucket.fluentbit.id
  key    = "${var.service_name}-${local.ecs_cluster}-fluentbit.conf"
  content = local.fluentbit_config
}
```
The general path our logs take is: 

```
Container StdOut/StdErr -> Firelens sidecar running fluentbit --> Datadog
                                                              \-> AWS Firehose ArchiveStream -> S3 archive bucket 
```
## Other things you can do:

# remove lines from the log via regex

This is added for you in the current log-config, but if there were other lines you would prefer to leave out of the logs, you can add additional filters to match them with this config:

```
[FILTER]
    Name    grep
    Match   *
    Exclude log {regex_expr}
```

This tells fluentbit to use the grep filter (https://docs.fluentbit.io/manual/data-pipeline/filters/grep) and evaluate every entry that comes through. If the "log" field matches the regular expression the entry will be silently discarded

You can find more about configuring Fluent-bit here: https://docs.fluentbit.io/manual/administration/configuring-fluent-bit/classic-mode/configuration-file

It's quite complex!
