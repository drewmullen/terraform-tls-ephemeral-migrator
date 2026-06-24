variable "tls_private_key_data" {
  description = "Legacy private key PEM. Set only when migrating existing deployments to remove secret from state. Leave null for new deployments."
  type        = string
  ephemeral   = true
  sensitive   = true
  default     = null
}

variable "secret_version" {
  description = "Increment to trigger a re-write of the write-only secret."
  type        = number
  default     = 1
}
