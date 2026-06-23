# terraform-tls-ephemeral-migrator

Example Terraform module demonstrating full removal of TLS private keys from state using ephemeral resources. Secrets are never written to Terraform state.

## Usage

```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"
}
```

To rotate the ephemeral secret, increment `secret_version`:

```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"

  secret_version = 2
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `secret_version` | `number` | `1` | Increment to trigger a re-write of the write-only Vault secret. |

## Resources

| Name | Type | Notes |
|------|------|-------|
| `ephemeral.tls_private_key.this` | `tls_private_key` | Generated ephemerally — never in state |
| `vault_kv_secret_v2.legacy` | `vault_kv_secret_v2` | Write-only secret (`data_json_wo`) — value never read back |

## Upgrading

Users on v1.x upgrading directly to v2.0 must first upgrade to v1.2 and complete the one-time migration step.
See [docs/UPGRADE-GUIDE-v2.0.0.md](docs/UPGRADE-GUIDE-v2.0.0.md) for full instructions.

## References

- [Blog post: Fully migrate secrets out of Terraform module state without breaking existing users](https://dev.to/drewmullen/fully-migrate-secrets-out-of-terraform-module-state-without-breaking-existing-users-1jc5)
- [Policy library: ephemerality](https://github.com/drewmullen/policy-library-ephemerality)
