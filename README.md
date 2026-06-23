# terraform-tls-ephemeral-migrator

Terraform module demonstrating ephemeral resource migration pattern.

## Features

- TLS private key generation
- Vault KV secret storage
- Ephemeral mode support (v1.1+)

## Usage

### Legacy Mode (Default in v1.x)

```hcl
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
}
```

Secrets stored in Terraform state (legacy behavior).

### Ephemeral Mode (Available in v1.1+, Default in v2.0+)

```hcl
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
  
  use_ephemeral_key = true
}
```

Secrets never stored in Terraform state.

## Variables

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `use_ephemeral_key` | Use ephemeral key (not stored in state) | `bool` | `false` (v1.x), `true` (v2.0+) |
| `secret_version` | Increment to rotate key (ephemeral mode only) | `number` | `1` |

## Resources

| Name | Type | Mode |
|------|------|------|
| `tls_private_key.legacy_resource[0]` | resource | Legacy |
| `tls_private_key.ephemeral[0]` | ephemeral | Ephemeral |
| `vault_kv_secret_v2.secret[0]` | resource | Both |

## Upgrade Guides

- [v1.1 Migration](./docs/UPGRADE-GUIDE-1.1.md) - Adding ephemeral support
- [v2.0 Migration](./docs/UPGRADE-GUIDE-2.0.md) - Defaulting to ephemeral mode
- [Upgrade Procedures](./docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) - Step-by-step upgrade assistant

## Requirements

- Terraform >= 1.11 (ephemeral support)
- Vault provider >= 5.9.0

## Related

- [Ephemeral Migration Blog Post](https://dev.to/drewmullen/migrating-a-terraform-module-to-ephemeral-resources-without-breaking-existing-users-g2o)
- [Policy Library](https://github.com/drewmullen/policy-library-ephemerality)
