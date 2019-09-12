variable "prefix" {
}

variable "resource_group_name" {
}

variable "endpoint_targets" {
  description = "List of two FQDNs for which Traffic Manager endpoints will be created"
}

resource "azurerm_traffic_manager_profile" "tm-profile" {
  resource_group_name    = "${var.resource_group_name}"
  name                   = "petre-${var.prefix}-tm-profile"
  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "petre-${var.prefix}-tm"
    ttl           = 100
  }

  monitor_config {
    protocol                     = "http"
    port                         = 80
    path                         = "/"
    interval_in_seconds          = 30
    timeout_in_seconds           = 9
    tolerated_number_of_failures = 3
  }
}

resource "azurerm_traffic_manager_endpoint" "tm-primary-endpoint" {
  name                = "petre-primary-tm"
  resource_group_name = "${var.resource_group_name}"
  profile_name        = "${azurerm_traffic_manager_profile.tm-profile.name}"
  target              = "${var.endpoint_targets[0]}"
  type                = "externalEndpoints"
  priority            = "1"
}

resource "azurerm_traffic_manager_endpoint" "tm-secondary-endpoint" {
  name                = "petre-secondary-tm"
  resource_group_name = "${var.resource_group_name}"
  profile_name        = "${azurerm_traffic_manager_profile.tm-profile.name}"
  target              = "${var.endpoint_targets[1]}"
  type                = "externalEndpoints"
  priority            = "100"
}

output "name" {
  value = "${azurerm_traffic_manager_profile.tm-profile.name}"
}

output "profile_id" {
  value = "${azurerm_traffic_manager_profile.tm-profile.id}"
}

output "primary_endpoint_name" {
  value = "${azurerm_traffic_manager_endpoint.tm-primary-endpoint.name}"
}