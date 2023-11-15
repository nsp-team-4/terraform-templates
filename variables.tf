# Allowed IP prefixes (CIDR notation)
variable "allowed_ip_prefixes" {
  description = "The IP prefixes that are allowed to connect to the AIS receiver container."
  type        = list(string)
  default = [
    "86.92.2.242",
    "212.115.197.130",
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
  default     = "storagenspais"
}

# Event hub namespace name
variable "eventhub_namespace_name" {
  description = "The name of the event hub namespace."
  type        = string
  default     = "ais-events"
}
