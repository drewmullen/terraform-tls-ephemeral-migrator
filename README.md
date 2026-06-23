# terraform-tls-ephemeral-migrator

Example Terraform module demonstrating ephemeral resource migration for TLS private keys and Vault secrets.

## Usage

### Legacy Mode (secrets in state)

```hcl
module "example" {
  source = "..."

  use_ephemeral_key = false
}
```

### Ephemeral Mode (secrets never in state — recommended for v1.1+)

```hcl
module "example" {
  source = "..."

  use_ephemeral_key = true
}
```

### Rotating Ephemeral Secrets

```hcl
module "example" {
  source = "..."

  use_ephemeral_key = true
  secret_version    = 2  # increment to force key rotation
}
```

## Variables

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `use_ephemeral_key` | `bool` | `false` (v1.x) / `true` (v2.x) | Use ephemeral key (not stored in state) |
| `secret_version` | `number` | `1` | Increment to rotate key (ephemeral mode only) |

## Resources

| Name | Type | Ephemeral |
|------|------|-----------|
| `tls_private_key.legacy` | `tls_private_key` | No (count=1 in legacy mode) |
| `ephemeral.tls_private_key.ephemeral` | `tls_private_key` | Yes (ephemeral mode) |
| `vault_kv_secret_v2.legacy` | `vault_kv_secret_v2` | Partial (write-only in ephemeral mode) |

## Upgrading

- [UPGRADE-GUIDE-v2.0.0.md](./docs/UPGRADE-GUIDE-v2.0.0.md) — Full upgrade guide for v1.x → v2.0
- [Upgrade Assistant Skill](./docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) — Step-by-step upgrade procedures with state extraction and validation

## References

- [Blog post: Migrating a Terraform module to ephemeral resources without breaking existing users](https://dev.to/drewmullen/migrating-a-terraform-module-to-ephemeral-resources-without-breaking-existing-users-g2o)
- [Policy library: ephemerality](https://github.com/drewmullen/policy-library-ephemerality)
