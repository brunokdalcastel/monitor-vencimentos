terraform {
  required_version = ">= 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}

  # Sem isso, a checagem interna de "a Storage Account já está disponível" que o
  # provider faz logo após criar o recurso usa autenticação por CHAVE por padrão —
  # e falha com 403 porque shared_access_key_enabled = false (D3). Descoberto na
  # prática no primeiro apply real (ver Pendências da T12 no PLANO.md).
  storage_use_azuread = true
}

provider "azuread" {}
