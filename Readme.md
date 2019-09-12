# Description

This will create two Ubuntu VMs in separate regions plus a Traffic Manager profile and its respective endpoints.
Ansible will also be run for each managed VM and run the /ansible/webapp/main.yml playbook.

## Overview

Two terraform modules are used:
- __vm__ for creating an Ubuntu VM with a public IP and a relative DNS record, which accepts connections on ports 22 and 80. This module outputs its public FQDN.
- __traffic-manager__ which accepts a list of 2 FQDNs which will be set as priority endpoints in the order they are provided.

Additionally, two more items are created:
- __key vault__ to store the admin password plus the private SSH key which is copied from ~/.ssh/id_rsa
    > The key vault and relevant secrets will only be created if the `user_object_id` (see below) is provided
- __monitor alerts__ which send out emails when the Traffic Manager's primary endpoint is down
    > The alert is created after ansible finishes, however, a misfire can happen if the alert creation is finished before nginx had a chance to start.

## Configure

### credentials.auto.tfvars
- __subscription_id__: The Azure Subscription ID where the deployment occurs
- __tenant_id__: The Azure Active Directory Tenant ID
- __user_object_id__ (optional): The AAD object id of the user logged in to AAD. This is required for setting Key Vault access policies.
    
> The latter is needed for Azure CLI authentication to work, so we can instruct Terraform to which user to provide Azure Key Vault Secret Write permissions. Basically, it's a hack since we can't obtain this ID script-side without a complex workaround. = If not set, the key vault will not be created.

### names.auto.tfvars
-   __azurerm_resource_group_name__: The target Azure Resource Group for the deployment
-   __prefix__: A unique key (3-8 characters) to ensure unique resource names and FQDNs.

### Prerequisites
1.  Make sure you are running on Linux
2.  Generate an SSH key pair under ~/.ssh/id_rsa and ~/.ssh/id_rsa.pub
    ```
    ssh-keygen -t rsa -b 2048
    ```
3. Install the following
    -   Azure CLI
    -   Terraform
    -   Ansible
4.  Log yourself into Azure with the CLI
    ```
    az login
    ```

## Run

Simply install the providers via init and apply the terraform desired state
```
terraform init
terraform apply
```

The final output will contain the URL of your newly deployed environment
