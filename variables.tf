
variable "service_name" {
  type        = string
  description = "The name of the service."
}

variable "datadog_api_key" {
  type        = string
  description = "api key to talk to datadog with."
}

variable "sourcetype" {
  type        = string
  description = "The name of the logfile / sourcetype."
}

variable "tags" {
  type        = string
}

variable "ecs_cluster" {
  type        = string
  description = "The name of the cluster."
}

variable "custom_fluentbit_config" {
  type        = string
  description = "HEREDOC with custom fluentbit options."
  default = ""
}

