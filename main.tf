moved {
  from = tls_private_key.legacy
  to   = tls_private_key.legacy[0]
}

resource "tls_private_key" "legacy" {
  count     = var.use_ephemeral_key ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 4096
}

ephemeral "tls_private_key" "ephemeral" {
  count     = var.use_ephemeral_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vault_kv_secret_v2" "legacy" {
  mount = "kvv2"
  name  = "mytls"

  # Legacy path - persisted to state
  data_json = var.use_ephemeral_key ? null : jsonencode({
    private_key = one(tls_private_key.legacy[*].private_key_pem)
  })

  # Ephemeral path - write-only, never read back
  data_json_wo = var.use_ephemeral_key ? jsonencode({
    private_key = one(ephemeral.tls_private_key.ephemeral[*].private_key_pem)
  }) : null

  # Version tracking for ephemeral updates (write-only attrs never diffed)
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
