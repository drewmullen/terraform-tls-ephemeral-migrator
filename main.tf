moved {
  from = tls_private_key.legacy
  to   = tls_private_key.legacy[0]
}

removed {
  lifecycle {
    destroy = false
  }
  from = tls_private_key.legacy[0]
}

ephemeral "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vault_kv_secret_v2" "legacy" {
  mount = "kvv2"
  name  = "mytls"

  data_json_wo = var.tls_private_key_data != null ? jsonencode(
    { private_key = var.tls_private_key_data }) : jsonencode(
    { private_key = ephemeral.tls_private_key.this.private_key_pem })

  data_json_wo_version = var.secret_version
}

terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.9.0"
    }
  }
}
