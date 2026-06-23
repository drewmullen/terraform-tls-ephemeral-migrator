# terraform-tls-ephemeral-migrator

Example Terraform module demonstrating full removal of TLS private keys from state using ephemeral resources. Secrets are never written to state for new deployments. Existing users can perform a one-time migration step to preserve their secret value while removing it from state.

## Usage

### New Deployments

No extra configuration needed — secrets are ephemeral and never written to state.

```hcl
module "example" {
  source  = "..."
  version = "~> 1.2"
}
```

### Existing Deployments (one-time migration)

Extract your current private key from state, pass it as `tls_private_key_data` on the first apply after upgrading. After a successful apply, remove the variable.

```hcl
module "example" {
  source  = "..."
  version = "~> 1.2"

  # One-time migration only — remove after successful apply
  # tls_private_key_data = var.tls_private_key_data
}
```

See [docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md](docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) for the complete step-by-step upgrade procedure.

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `tls_private_key_data` | `string` (ephemeral, sensitive) | `null` | Legacy private key PEM. Pass only on the first apply when migrating existing deployments. Leave null for new deployments. |
| `secret_version` | `number` | `1` | Increment to trigger a re-write of the write-only Vault secret. |

## Resources

| Name | Type | Notes |
|------|------|-------|
| `ephemeral.tls_private_key.this` | `tls_private_key` | Generated ephemerally — never in state |
| `vault_kv_secret_v2.legacy` | `vault_kv_secret_v2` | Write-only secret (`data_json_wo`) — value never read back |

## Upgrading

- [docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md](docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) — Step-by-step upgrade assistant for existing deployments

## References

- [Blog post: Fully migrate secrets out of Terraform module state without breaking existing users](https://dev.to/drewmullen/fully-migrate-secrets-out-of-terraform-module-state-without-breaking-existing-users-1jc5)
- [Policy library: ephemerality](https://github.com/drewmullen/policy-library-ephemerality)
