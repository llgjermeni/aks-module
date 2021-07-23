provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "resource_group" {
  name     = "my-rg"
  location = "East US"
}

resource "random_string" "aks_sp_password" {
  keepers = {
    env_name = "dev"
  }
  length           = 24
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  special          = true
  min_special      = 1
  override_special = "!@-_=+."
}

resource "random_string" "aks_sp_secret" {
  keepers = {
    env_name = "dev"
  }
  length           = 24
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  special          = true
  min_special      = 1
  override_special = "!@-_=+."
}
resource "azuread_application" "aks_sp" {
  display_name = "sp-aks"
}

resource "azuread_service_principal" "aks_sp" {
  application_id               = azuread_application.aks_sp.application_id
  app_role_assignment_required = false
}

resource "azuread_service_principal_password" "aks_sp" {
  service_principal_id = azuread_service_principal.aks_sp.id
  value                = random_string.aks_sp_password.result
  end_date_relative    = "8760h" # 1 year

  lifecycle {
    ignore_changes = [
      value,
      end_date_relative
    ]
  }
}

resource "azuread_application_password" "aks_sp" {
  application_object_id = azuread_application.aks_sp.id
  value                 = random_string.aks_sp_secret.result
  end_date_relative     = "8760h" # 1 year

  lifecycle {
    ignore_changes = [
      value,
      end_date_relative
    ]
  }
}

module "vnet" {
  source              = "./modules/vnet"
  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  address_space       = ["10.0.0.0/16"]
  subnet_prefixes     = ["10.0.1.0/24"]
  subnet_names        = ["subnet1"]

  tags = {
    environment = "dev"
    author  = "Llazar Gjermeni"
  }

  depends_on = [azurerm_resource_group.resource_group]
}

# Attach the acr with aks
resource "azurerm_role_assignment" "aks_sp_container_registry" {
  scope                = module.acr.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azuread_service_principal.aks_sp.object_id

  depends_on = [
    module.aks,
    module.acr
  ]
}

module "acr" {
  source  = "./modules/acr"

  resource_group_name = azurerm_resource_group.resource_group.name
  location            = azurerm_resource_group.resource_group.location
  sku                 = "Standard"

  client_name  = "test-name"
  environment  = "development"
  stack        = "CD"
}

resource "azuread_group" "aks_cluster_admins" {
  display_name = "AKS-cluster-admins"
}

module "aks" {
  source                           = "./modules/aks"
  resource_group_name              = azurerm_resource_group.resource_group.name
  location                         = azurerm_resource_group.resource_group.location

  # Create client_id and client_secret by folllowing this link https://docs.microsoft.com/en-us/azure/active-directory/develop/howto-create-service-principal-portal 
  client_id                        = azuread_service_principal.aks_sp.application_id  #"your-service-principal-client-appid"
  client_secret                    = random_string.aks_sp_password.result    # "your-service-principal-client-password"
  kubernetes_version               = "1.21.1"
  orchestrator_version             = "1.21.1"
  prefix                           = "cluster"
  cluster_name                     = "aks-name"
  network_plugin                   = "azure"
  vnet_subnet_id                   = module.vnet.vnet_subnets[0]
  os_disk_size_gb                  = 50
  sku_tier                         = "Paid" # defaults to Free
  enable_role_based_access_control = true
  rbac_aad_admin_group_object_ids  = [azuread_group.aks_cluster_admins.id]
  rbac_aad_managed                 = true
  private_cluster_enabled          = true # default value
  enable_http_application_routing  = true
  enable_azure_policy              = true
  enable_auto_scaling              = true
  enable_host_encryption           = false
  agents_min_count                 = 1
  agents_max_count                 = 2
  agents_count                     = null # Please set `agents_count` `null` while `enable_auto_scaling` is `true` to avoid possible `agents_count` changes.
  agents_max_pods                  = 100
  agents_pool_name                 = "exnodepool"
  agents_availability_zones        = ["1", "2"]
  agents_type                      = "VirtualMachineScaleSets"

  agents_labels = {
    "nodepool" : "defaultnodepool"
  }

  agents_tags = {
    "Agent" : "defaultnodepoolagent"
  }

  network_policy                 = "azure"
  net_profile_dns_service_ip     = "10.30.0.10"
  net_profile_docker_bridge_cidr = "170.10.0.1/16"
  net_profile_service_cidr       = "10.30.0.0/16"

  depends_on = [module.vnet]
}