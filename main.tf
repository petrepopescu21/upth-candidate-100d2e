variable "subscription_id" {}
variable "tenant_id" {}
variable "user_object_id" {}
variable "prefix" {}
variable "azurerm_resource_group_name" {}
variable "regions" {
  description = "List of primary and secondary regions, in order, for the VM locations"
  default = {
    primary   = "West Europe"
    secondary = "North Europe"
  }
}
variable "ssh_pub_key" {
  default = "~/.ssh/id_rsa.pub"
}
variable "ssh_priv_key" {
  default = "~/.ssh/id_rsa"
}
variable "alert_to_email" {
  default = "youremail@address.com"
}

provider "azurerm" {
  version         = "=1.33.1"
  subscription_id = "${var.subscription_id}"
  tenant_id       = "${var.tenant_id}"
}

provider "tls" {
  version = "=2.1.0"
}

provider "random" {
  version = "=2.2.0"
}

# Loading the null provider for running ansible
provider "null" {
  version = "=2.1.2"
}

resource "azurerm_resource_group" "main" {
  name     = "${var.azurerm_resource_group_name}"
  location = "${var.regions.primary}"
}

# Generate SSH password and write inventory variables
resource "random_password" "password" {
  length  = 16
  special = true
}

module "vm_primary" {
  source              = "./vm"
  resource_group_name = "${azurerm_resource_group.main.name}"
  prefix              = "${var.prefix}-primary"
  location            = "${var.regions.primary}"
  admin_password      = "${random_password.password.result}"
  ssh_pub_key = "${var.ssh_pub_key}"
  ssh_priv_key = "${var.ssh_priv_key}"
}

module "vm_secondary" {
  source              = "./vm"
  resource_group_name = "${azurerm_resource_group.main.name}"
  prefix              = "${var.prefix}-secondary"
  location            = "${var.regions.secondary}"
  admin_password      = "${random_password.password.result}"
  ssh_pub_key = "${var.ssh_pub_key}"
  ssh_priv_key = "${var.ssh_priv_key}"
}

module "traffic_manager" {
  source              = "./traffic-manager"
  resource_group_name = "${azurerm_resource_group.main.name}"
  prefix              = "${var.prefix}"
  endpoint_targets = [
    "${module.vm_primary.vm_public_name}",
    "${module.vm_secondary.vm_public_name}"
  ]
}

# Create Action Group to send alerts to myself
resource "azurerm_monitor_action_group" "emaction" {
  name                = "EndpointMonitoringAction-${var.prefix}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  short_name          = "ac-${var.prefix}"
  email_receiver {
    name          = "sendtocandidate"
    email_address = "petrepopescu21@gmail.com"
  }
}

# Create Alert Rule for Traffic Manager Monitoring
resource "azurerm_monitor_metric_alert" "primary_endpoint" {
  depends_on = ["module.vm_primary.vm_public_name"]
  name                = "${module.traffic_manager.name}-alert"
  resource_group_name = "${azurerm_resource_group.main.name}"
  scopes              = ["${module.traffic_manager.profile_id}"]
  description         = "An alert which fires when the Primary endpoint for the Traffic Manager is down"

  frequency   = "PT1M"
  window_size = "PT5M"

  criteria {
    metric_namespace = "Microsoft.Network/trafficManagerProfiles"
    metric_name      = "ProbeAgentCurrentEndpointStateByProfileResourceId"
    operator         = "LessThan"
    threshold        = 1
    aggregation      = "Minimum"
    dimension {
      name     = "EndpointName"
      operator = "Include"
      values   = ["${module.traffic_manager.primary_endpoint_name}"]
    }
  }

  action {
    action_group_id = "${azurerm_monitor_action_group.emaction.id}"
  }
}

#Create Key Vault to store admin passwords and private SSH keys for the VMs

resource "azurerm_key_vault" "kv" {
  # Conditionally deploy this if user_object_id is not empty
  count = "${var.user_object_id != "" ? 1 : 0}"

  name                = "petre-${var.prefix}-kv"
  location            = "${var.regions.primary}"
  resource_group_name = "${azurerm_resource_group.main.name}"
  tenant_id           = "${var.tenant_id}"
  sku_name            = "standard"
  access_policy {
    tenant_id = "${var.tenant_id}"
    object_id = "${var.user_object_id}"

    secret_permissions = [
      "set",
      "get",
      "delete",
      "list"
    ]
  }
}

resource "azurerm_key_vault_secret" "vm-ansible-pass" {
  # Conditionally deploy this if user_object_id is not empty
  count = "${var.user_object_id != "" ? 1 : 0}"

  name         = "ansible-password"
  value        = "${random_password.password.result}"
  key_vault_id = "${azurerm_key_vault.kv[count.index].id}"
  content_type = "text/plain"
}

resource "azurerm_key_vault_secret" "vm-ansible-key" {
  # Conditionally deploy this if user_object_id is not empty
  count = "${var.user_object_id != "" ? 1 : 0}"
  
  name         = "ansible-private-key"
  value        = "${file(var.ssh_priv_key)}"
  key_vault_id = "${azurerm_key_vault.kv[count.index].id}"
  content_type = "text/plain"
}

output "traffic_manager_url" {
  value = "https://${module.traffic_manager.name}.trafficnamanger.net"
}