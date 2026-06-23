variable "use_ephemeral_key" {
  description = "Use ephemeral key (not stored in state)"
  type        = bool
  default     = false
}

variable "secret_version" {
  description = "Increment to rotate key (ephemeral mode only)"
  type        = number
  default     = 1
}
