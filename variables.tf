variable "tls_private_key_data" {
  description = "Legacy private key PEM value. Set only when migrating existing deployments to remove the secret from state. Leave null for new deployments."
  type        = string
  ephemeral   = true
  sensitive   = true
  default     = null
}

variable "secret_version" {
  description = "Increment to trigger a re-write of the secret. Only relevant when tls_private_key_data is null."
  type        = number
  default     = 1
}
