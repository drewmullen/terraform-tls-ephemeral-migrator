# Ephemeral Migration Summary

## Module: terraform-tls-ephemeral-migrator

### Changes Required

**Variables Added:**
- `use_ephemeral_key` (bool, default: false) - enables ephemeral mode
- `secret_version` (number, default: 1) - increment to force rotation

**Files Modified:**
- `main.tf` - migrated 1 resource + 1 consumer
- `variables.tf` - added toggle variables

### Resource Migrations

#### 1. tls_private_key.legacy → ephemeral (main.tf:1)
**Category:** ephemeral-creates  
**Changes:**
- Added toggle variable `use_ephemeral_key`
- Split into `legacy_mode` (count) and `ephemeral` (count) resources
- Added `moved` block: `tls_private_key.legacy` → `tls_private_key.legacy_mode[0]`
- Updated 1 consumer with separate attribute paths

**Consumers updated:**
- `vault_kv_secret_v2.storage` - now uses `data_json` vs `data_json_wo`

#### 2. vault_kv_secret_v2.legacy → write-only (main.tf:6)
**Category:** write-only
**Changes:**
- Added `data_json_wo` attribute for ephemeral path
- Added `data_json_wo_version` for rotation tracking
- Updated `data_json` to use ternary with `one()` pattern
- Added `moved` block: `vault_kv_secret_v2.legacy` → `vault_kv_secret_v2.storage[0]`

**Write-only attributes available:**
- `data_json_wo` - replaces `data_json` in ephemeral mode

### User Migration Path

**For existing users (no changes required):**
- Module defaults to `use_ephemeral_key = false`
- All resources remain in state
- No destroy/create operations

**For new users (recommended):**
```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  # Enable ephemeral mode
  use_ephemeral_key = true
}
```

**For existing users migrating to ephemeral:**
1. Upgrade module version
2. Run `terraform plan` - should see `moved` messages, no destroys
3. Set `use_ephemeral_key = true`
4. Run `terraform apply` - existing key regenerated
5. Old key removed from state

**To rotate ephemeral secrets:**
```hcl
module "example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  use_ephemeral_key = true
  secret_version    = 2  # increment to force rotation
}
```

### Testing

```bash
# Verify legacy mode (existing users)
terraform plan

# Verify ephemeral mode (new users)
terraform plan -var="use_ephemeral_key=true"

# Verify migration path
terraform plan  # should show moved blocks
terraform plan -var="use_ephemeral_key=true"  # should show recreates
```

### Next Steps

1. Test module with both `use_ephemeral_key = false` and `true`
2. Update module README with migration guide
3. Tag new minor version (e.g., v1.0.0)
4. Consider flipping defaults in next major version (v2.0.0)
