moved {
  from = tls_private_key.legacy
  to   = tls_private_key.legacy_mode[0]
}

resource "tls_private_key" "legacy_mode" {
  count     = var.use_ephemeral_key ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

ephemeral "tls_private_key" "ephemeral" {
  count     = var.use_ephemeral_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

moved {
  from = vault_kv_secret_v2.legacy
  to   = vault_kv_secret_v2.storage[0]
}

resource "vault_kv_secret_v2" "storage" {
  count = 1
  mount = "kvv2"
  name  = "mytls"

  data_json = var.use_ephemeral_key ? null : jsonencode({
    private_key = one(tls_private_key.legacy_mode[*].private_key_pem)
  })

  data_json_wo = var.use_ephemeral_key ? jsonencode({
    private_key = one(ephemeral.tls_private_key.ephemeral[*].private_key_pem)
  }) : null

  data_json_wo_version = var.use_ephemeral_key ? var.secret_version : null
}

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.9.0"
    }
  }
}