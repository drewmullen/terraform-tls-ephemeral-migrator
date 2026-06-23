# Upgrade from v1.0 to v1.1

## What's New

v1.1 adds support for ephemeral resources to remove secrets from Terraform state while maintaining backward compatibility with existing deployments.

## Changes

### New Variables

- `use_ephemeral_key` (bool, default: `false`) - Enable ephemeral mode for TLS private key
- `secret_version` (number, default: `1`) - Force secret rotation in ephemeral mode

### Migrated Resources

#### 1. tls_private_key.legacy → ephemeral

- **Old state address:** `tls_private_key.legacy`
- **New state address (legacy mode):** `tls_private_key.legacy_resource[0]`
- **New state address (ephemeral mode):** `ephemeral.tls_private_key.ephemeral[0]`

#### 2. vault_kv_secret_v2.legacy → write-only support

- **Old state address:** `vault_kv_secret_v2.legacy`
- **New state address:** `vault_kv_secret_v2.secret[0]`
- **Write-only attribute:** `data_json_wo` - replaces `data_json` in ephemeral mode

### How It Works

Resources split into dual paths controlled by toggle variables:
- **Legacy path** (`use_ephemeral_key = false`, default): secrets in state (existing behavior)
- **Ephemeral path** (`use_ephemeral_key = true`): secrets never written to state

## Migration Path

### For Existing Users (No Changes Required)

Module defaults to `use_ephemeral_key = false`. All resources remain in state. No destroy/create operations.

**Before (v1.0):**
```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
}
```

**After (v1.1):**
```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
}
```

**Steps:**
1. Update module version to v1.1
2. Run `terraform plan` - should show only `moved` operations
3. Run `terraform apply`

**Result:** Secrets remain in state, no regeneration.

### For New Users (Recommended)

Adopt ephemeral mode for improved security:

```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  use_ephemeral_key = true
}
```

**Result:** Secrets never stored in state.

### Rotating Ephemeral Secrets

```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  use_ephemeral_key = true
  secret_version    = 2  # increment to force rotation
}
```

## Testing

```bash
# Verify legacy mode (existing users)
terraform plan

# Verify ephemeral mode (new users)
terraform plan -var="use_ephemeral_key=true"

# Verify migration path
terraform plan  # should show moved blocks
terraform plan -var="use_ephemeral_key=true"  # should show recreates
```

## Next Steps

1. Test module with both `use_ephemeral_key = false` and `true`
2. Consider flipping defaults in next major version (v2.0.0)

## Related Documentation

- [Upgrade Procedures](./skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) - Step-by-step upgrade guide
- [v2.0 Upgrade Guide](./UPGRADE-GUIDE-2.0.md) - Major version migration paths
