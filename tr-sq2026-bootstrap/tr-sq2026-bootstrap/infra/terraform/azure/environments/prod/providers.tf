terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.75"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-turksquare-tfstate"
    storage_account_name = "stturktfstateprod"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
    subscription_id      = "ae28daea-9900-4161-8c87-dc2fa5951304"
    tenant_id            = "c04e6d5b-5a24-42bc-b75b-31915d61e2ed"
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
  features {
    key_vault {
      purge_soft_delete_on_destroy    = false
      recover_soft_deleted_key_vaults = true
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
