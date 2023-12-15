variable "env_name" {
  description = "The environment in which the resources will be deployed. Will be used as a suffix for the resource names."
  type        = string
  default     = "test" # Options: test, prod
}

variable "allowed_ips" {
  description = "The IP prefixes (CIDR notation) that are allowed to connect to the AIS receiver container."
  type        = list(string)
  default = [
    "86.92.2.242",     # Home
    "212.115.197.141", # NSP Location 1
    "212.115.197.130", # NSP Location 2
    "145.19.248.127",  # School
  ]
}

locals {
  # The name of the resource group.
  resource_group_name = "north-sea-port-${var.env_name}"

  # The domain name label for the public IP address.
  domain_name_label = "ais-receiver-${var.env_name}"

  # The name of the container (group).
  container_name = "ais-receiver-${var.env_name}"

  # The name of the network security group.
  network_security_group_name = "ais-network-security-group-${var.env_name}"

  # The name of the storage account.
  storage_account_name = "aisnspstorage${var.env_name}"

  # The name of the Event Hub namespace.
  eventhub_namespace_name = "ais-events-namespace-${var.env_name}"

  # The name of the Stream Analytics job.
  stream_analytics_job_name = "ais-stream-job-${var.env_name}"
}

variable "frontend_ip_name" {
  description = "The name of the frontend IP configuration."
  type        = string
  default     = "ais-frontend-ip-config"
}

variable "stream_analytics_job_input_name" {
  description = "The name of the streaming job input."
  type        = string
  default     = "ais-stream-job-input"
}

variable "stream_analytics_job_output_name" {
  description = "The name of the streaming job output."
  type        = string
  default     = "ais-stream-job-output"
}

variable "stream_analytics_job_capacity" {
  description = "The number of streaming units that the streaming job uses."
  type        = number
  default     = 10 # A minimum of 10 streaming units is required to run in a virtual network.
}

variable "stream_analytics_api_version" {
  description = "The API version of the stream analytics job."
  type        = string
  default     = "Microsoft.StreamAnalytics/streamingJobs@2021-10-01-preview"
}

variable "container_port" {
  description = "The port on which the container listens."
  type        = number
  default     = 2001
}

# adf -> Azure Data Factory
# rg -> Resource Group
