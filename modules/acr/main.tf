locals {
  acr_default_name_long = replace("${var.name_prefix}${var.stack}${var.client_name}${var.environment}acr", "/\\W/", "")
  acr_name = coalesce(
    var.custom_name,
    substr(
      local.acr_default_name_long,
      0,
      length(local.acr_default_name_long) > 50 ? 49 : -1,
    ),
  )

  default_tags = {
    env   = var.environment
    stack = var.stack
  }
}

resource "azurerm_container_registry" "registry" {
  name = lower(local.acr_name)

  location            = var.location
  resource_group_name = var.resource_group_name

  sku           = var.sku
  admin_enabled = var.admin_enabled


  tags = merge(local.default_tags, var.extra_tags)
}