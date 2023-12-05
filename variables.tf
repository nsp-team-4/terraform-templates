# Allowed IP prefixes (CIDR notation)
variable "allowed_ips" {
  description = "The IP prefixes that are allowed to connect to the AIS receiver container."
  type        = list(string)
  default = [
    "86.92.2.242", # Home
    "212.115.197.141", # NSP
    "145.19.248.127", # School
  ]
}

# Domain name label for the public IP
variable "domain_name_label" {
  description = "The domain name label for the public IP."
  type        = string
  default     = "ais-receiver"
}

# Storage account name for events
variable "storage_account_name" {
  description = "The name of the storage account for events."
  type        = string
  default     = "aisnspstorage"
}

# Event hub namespace name
variable "eventhub_namespace_name" {
  description = "The name of the event hub namespace."
  type        = string
  default     = "ais-events"
}

# Stream analytics job name
variable "stream_analytics_job_name" {
  description = "The name of the streaming job."
  type        = string
  default     = "ais-stream-job"
}

# Stream analytics job input name
variable "stream_analytics_job_input_name" {
  description = "The name of the streaming job input."
  type        = string
  default     = "ais-stream-job-input"
}


# Stream analytics job output name
variable "stream_analytics_job_output_name" {
  description = "The name of the streaming job output."
  type        = string
  default     = "ais-stream-job-output"
}
