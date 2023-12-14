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

variable "domain_name_label" {
  description = "The domain name label for the public IP."
  type        = string
  default     = "ais-receiver"
}

variable "storage_account_name" {
  description = "The name of the storage account for events."
  type        = string
  default     = "aisnspstorage"
}

variable "eventhub_namespace_name" {
  description = "The name of the event hub namespace."
  type        = string
  default     = "ais-events-namespace"
}

variable "stream_analytics_job_name" {
  description = "The name of the streaming job."
  type        = string
  default     = "ais-stream-job"
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
