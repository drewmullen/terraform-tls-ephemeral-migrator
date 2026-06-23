resource "tls_private_key" "legacy" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "vault_kv_secret_v2" "legacy" {
  mount     = "kvv2"
  name      = "mytls"
  data_json = jsonencode({ private_key = tls_private_key.legacy.private_key_pem })
}
