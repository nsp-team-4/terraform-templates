# One day this file can be refactored massively once the azurerm provider supports the new Stream Analytics API. 
# Stream Analytics Job
resource "azapi_resource" "this" {
  type      = var.stream_analytics_api_version
  name      = "stream-ais-job"
  parent_id = azurerm_resource_group.this.id
  location  = azurerm_resource_group.this.location

  identity {
    type = "SystemAssigned"
  }

  body = jsonencode({
    properties = {
      compatibilityLevel   = "1.2"
      contentStoragePolicy = "JobStorageAccount"

      externals = {
        container = var.stream_analytics_job_output_name
        path      = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"

        storageAccount = {
          accountKey         = azurerm_storage_account.events.primary_access_key
          accountName        = azurerm_storage_account.events.name
          authenticationMode = "Msi"
        }
      }

      jobStorageAccount = {
        accountName        = azurerm_storage_account.events.name
        authenticationMode = "Msi"
      }

      sku = {
        capacity = var.stream_analytics_job_capacity
        name     = "StandardV2"
      }

      transformation = null
    }

    sku = {
      capacity = var.stream_analytics_job_capacity
      name     = "StandardV2"
    }
  })

  response_export_values = [
    "id",
    "name",
  ]
}

# Add Azure Event Hubs Data Receiver role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_event_hub_role" {
  scope                = azurerm_eventhub_namespace.this.id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Add the Storage Blob Data Contributor role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_blob_role" {
  scope                = azurerm_storage_account.events.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Add the Storage Queue Data Contributor role assignment to the Managed Identity of the Stream Analytics Job.
resource "azurerm_role_assignment" "stream_table_role" {
  scope                = azurerm_storage_account.events.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azapi_resource.this.identity[0].principal_id
}

# Now update the Stream Analytics Job with the correct transformation.
resource "azapi_update_resource" "this" {
  type        = var.stream_analytics_api_version
  resource_id = replace(jsondecode(azapi_resource.this.output).id, "streamingjobs", "streamingJobs")
  body = jsonencode({
    properties = {
      externals = {
        container = var.stream_analytics_job_output_name
        path      = "year={datetime:yyyy}/month={datetime:MM}/day={datetime:dd}/hour={datetime:HH}"
        storageAccount = {
          accountKey         = azurerm_storage_account.events.primary_access_key
          accountName        = azurerm_storage_account.events.name
          authenticationMode = "Msi"
        }
      }

      transformation = {
        name = "main",
        properties = {
          query = templatefile("./sql/stream-analytics-job.sql", {
            input_name  = var.stream_analytics_job_input_name,
            output_name = var.stream_analytics_job_output_name,
          }),
          streamingUnits = var.stream_analytics_job_capacity,
        }
      }
    }
  })

  response_export_values = [
    "id",
    "name",
  ]

  depends_on = [
    azapi_resource.this,
    azurerm_role_assignment.stream_event_hub_role,
    azurerm_role_assignment.stream_blob_role,
    azurerm_role_assignment.stream_table_role,
  ]
}

resource "azapi_resource_action" "this" {
  type        = var.stream_analytics_api_version
  resource_id = replace(jsondecode(azapi_update_resource.this.output).id, "streamingjobs", "streamingJobs")
  method      = "PATCH"
  body = jsonencode({
    properties = {
      subnetResourceId = azurerm_subnet.stream.id
    }
  })

  depends_on = [
    azapi_update_resource.this
  ]
}

# Stream Analytics Job Input from Event Hub
resource "azurerm_stream_analytics_stream_input_eventhub_v2" "this" {
  name                      = var.stream_analytics_job_input_name
  stream_analytics_job_id   = replace(jsondecode(azapi_update_resource.this.output).id, "streamingjobs", "streamingJobs")
  eventhub_name             = azurerm_eventhub.this.name
  servicebus_namespace      = azurerm_eventhub_namespace.this.name
  authentication_mode       = "Msi"
  shared_access_policy_key  = azurerm_eventhub_namespace.this.default_primary_key
  shared_access_policy_name = "RootManageSharedAccessKey"

  serialization {
    type     = "Json"
    encoding = "UTF8"
  }
}

# Output Blob storage for the Stream Analytics Job
resource "azurerm_stream_analytics_output_blob" "this" {
  name                      = var.stream_analytics_job_output_name
  resource_group_name       = azurerm_resource_group.this.name
  stream_analytics_job_name = jsondecode(azapi_update_resource.this.output).name
  date_format               = "yyyy-MM-dd"
  path_pattern              = "{datetime:yyyy}/{datetime:MM}/{datetime:dd}/{datetime:HH}"
  time_format               = "HH"
  storage_account_name      = azurerm_storage_account.events.name
  authentication_mode       = "Msi"
  storage_account_key       = azurerm_storage_account.events.primary_access_key
  storage_container_name    = var.stream_analytics_job_output_name

  serialization {
    type     = "Json"
    encoding = "UTF8"
    format   = "LineSeparated"
  }
}

# Start the Stream Analytics Job
resource "azurerm_stream_analytics_job_schedule" "this" {
  stream_analytics_job_id = replace(jsondecode(azapi_update_resource.this.output).id, "streamingjobs", "streamingJobs")
  start_mode = "JobStartTime"

  depends_on = [
    azapi_resource_action.this,
  ]
}
