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

  data_json_wo         = jsonencode({ private_key = ephemeral.tls_private_key.this.private_key_pem })
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
