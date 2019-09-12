variable "prefix" {}
variable "resource_group_name" {
}
variable "location" {
  description = "Location for the VM"
}
variable "admin_username" {
  default = "rootadmin"
}
variable "admin_password" {}

resource "azurerm_virtual_network" "main" {
  name                = "petre-${var.prefix}-network"
  address_space       = ["10.0.0.0/16"]
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"
}

resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = "${var.resource_group_name}"
  virtual_network_name = "${azurerm_virtual_network.main.name}"
  address_prefix       = "10.0.2.0/24"
}

resource "azurerm_public_ip" "main" {
  name                    = "petre-${var.prefix}-pip"
  domain_name_label       = "petre-${var.prefix}"
  location                = "${var.location}"
  resource_group_name     = "${var.resource_group_name}"
  allocation_method       = "Dynamic"
  idle_timeout_in_minutes = 30
}

resource "azurerm_network_security_group" "main" {
  name                = "petre-${var.prefix}-nsg"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group_name}"

  security_rule {
    name                       = "allow_SSH"
    description                = "Allow SSH access"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_HTTP"
    description                = "Allow HTTP access"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface" "main" {
  name                      = "petre-${var.prefix}-nic"
  location                  = "${var.location}"
  resource_group_name       = "${var.resource_group_name}"
  network_security_group_id = "${azurerm_network_security_group.main.id}"

  ip_configuration {
    name                          = "petre-ipconfig"
    subnet_id                     = "${azurerm_subnet.internal.id}"
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = "${azurerm_public_ip.main.id}"
  }
}

resource "azurerm_virtual_machine" "main" {
  name                  = "petre-${var.prefix}-vm"
  location              = "${var.location}"
  resource_group_name   = "${var.resource_group_name}"
  network_interface_ids = ["${azurerm_network_interface.main.id}"]
  vm_size               = "Standard_D2s_v3"

  storage_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "18.04-LTS"
    version   = "latest"
  }

  storage_os_disk {
    name              = "petre-${var.prefix}-osdisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name  = "petre-${var.prefix}-vm"
    admin_username = "${var.admin_username}"
    admin_password = "${var.admin_password}"
  }

  os_profile_linux_config {
    disable_password_authentication = false
    ssh_keys {
      key_data = "${file("~/.ssh/id_rsa.pub")}"
      path     = "/home/${var.admin_username}/.ssh/authorized_keys"
    }
  }
}

data "azurerm_public_ip" "postdeploy" {
  # Wait for VM to complete so FQDN is available
  depends_on          = ["azurerm_virtual_machine.main"]
  name = "petre-${var.prefix}-pip"
  resource_group_name = "${var.resource_group_name}"
}

# Once VM is ready, we can run ansible on it
resource "null_resource" "run-ansible" {
  depends_on = ["data.azurerm_public_ip.postdeploy"]

  # Making sure SSH is accessible before attempting to run Ansible
  provisioner "remote-exec" {
    inline = ["echo 'I am ready!'"]
    connection {
      host = "${data.azurerm_public_ip.postdeploy.fqdn}"
      type = "ssh"
      user = "rootadmin"
      private_key = "${file("~/.ssh/id_rsa")}"
    }
  }

  provisioner "local-exec" {
    command = "ansible-playbook -i '${data.azurerm_public_ip.postdeploy.fqdn},' -u ${var.admin_username} --private-key ~/.ssh/id_rsa  ./ansible/webapp/main.yml -b"
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "false"
    }
  }
}

output "vm_public_name" {
  depends_on = ["null_resource.run-ansible"]
  value = "${data.azurerm_public_ip.postdeploy.fqdn}"
}

output "vm_name" {
  value = "${azurerm_virtual_machine.main.name}"
}


