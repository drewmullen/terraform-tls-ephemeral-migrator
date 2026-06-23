# Upgrade from v1.x to v2.0

This major version changes the default behavior for secret handling. Secrets are now **stored as ephemeral values by default** and never persisted to state. This improves security but requires migration for existing deployments.

## What Changed

### Default Behavior
- `use_ephemeral_key` variable now defaults to `true` (was `false`)
- Secrets no longer stored in Terraform state by default
- Existing users must explicitly opt-out to maintain legacy behavior

### Resources Affected

- **tls_private_key.legacy**
  - v1.x: `tls_private_key.legacy`
  - v2.0 (legacy): `tls_private_key.legacy[0]`
  - v2.0 (ephemeral): `ephemeral.tls_private_key.ephemeral[0]`
  
- **vault_kv_secret_v2.legacy**
  - v1.x: `vault_kv_secret_v2.legacy`
  - v2.0: `vault_kv_secret_v2.legacy[0]`
  - Uses `data_json` (legacy) or `data_json_wo` (ephemeral) attributes

### Breaking Changes

- **use_ephemeral_key** variable now defaults to `true`
- Secrets regenerated unless explicitly opted-out
- State addresses changed (handled by `moved` blocks)

---

## Upgrade Paths

### Path 1: Maintain Legacy Behavior (No Secret Regeneration)

Keep secrets in state, avoid regeneration.

**Before (v1.x):**
```hcl
module "example" {
  source  = "./terraform-tls-ephemeral-migrator"
  version = "~> 1.0"
}
```

**After (v2.0):**
```hcl
module "example" {
  source  = "./terraform-tls-ephemeral-migrator"
  version = "~> 2.0"
  
  # Opt-out of ephemeral mode
  use_ephemeral_key = false
}
```

**Steps:**
1. Update `version = "~> 2.0"`
2. Add `use_ephemeral_key = false`
3. Run `terraform plan` - should show:
   - `moved` operations (state address changes)
   - No resource changes
4. Run `terraform apply`

**Result:** Secrets remain in state, no regeneration.

---

### Path 2: Migrate to Ephemeral (Recommended)

Adopt ephemeral mode, remove secrets from state.

**⚠️ Warning:** This **regenerates all secrets**. Update external systems accordingly.

**Before (v1.x):**
```hcl
module "example" {
  source  = "./terraform-tls-ephemeral-migrator"
  version = "~> 1.0"
}
```

**After (v2.0):**
```hcl
module "example" {
  source  = "./terraform-tls-ephemeral-migrator"
  version = "~> 2.0"
  
  # Ephemeral mode is now default
  # Optionally explicit:
  # use_ephemeral_key = true
}
```

**Steps:**

1. **Backup state:**
   ```bash
   terraform state pull > tfstate-v1.backup
   ```

2. **Update module version:**
   ```hcl
   version = "~> 2.0"
   ```

3. **Plan upgrade:**
   ```bash
   terraform plan
   ```
   
   Expected output:
   - `moved` operations for state address changes
   - Destroy `tls_private_key.legacy[0]` (legacy mode count=0)
   - Create `ephemeral.tls_private_key.ephemeral[0]` (ephemeral mode count=1)
   - Update `vault_kv_secret_v2.legacy[0]` (switch from `data_json` to `data_json_wo`)
   - **Secrets will regenerate**

4. **Apply upgrade:**
   ```bash
   terraform apply
   ```

5. **Verify state cleaned:**
   ```bash
   terraform state pull | grep -iE "private_key|password|secret"
   ```
   
   Should show minimal/no sensitive values.

**Result:** Secrets removed from state, ephemeral mode active.

---

### Path 3: Staged Migration (Lower Risk)

For multi-secret modules, migrate one at a time. This module only has one toggle, so staged migration is the same as Path 2.

---

## Resource-Specific Migration

### tls_private_key.legacy

**Toggle:** `use_ephemeral_key`

**State addresses:**
- v1.x: `tls_private_key.legacy`
- v2.0 (legacy, `use_ephemeral_key = false`): `tls_private_key.legacy[0]`
- v2.0 (ephemeral, `use_ephemeral_key = true`): `ephemeral.tls_private_key.ephemeral[0]`

**Consumers:**
- `vault_kv_secret_v2.legacy[0].data_json` (legacy mode)
- `vault_kv_secret_v2.legacy[0].data_json_wo` (ephemeral mode)

**Migration:**

Legacy mode (v2.0):
```hcl
module "example" {
  use_ephemeral_key = false
}
```

Ephemeral mode (v2.0 default):
```hcl
module "example" {
  # Defaults to true
  # use_ephemeral_key = true
}
```

**Rotation (ephemeral mode only):**
```hcl
module "example" {
  secret_version = 2  # increment to regenerate
}
```

---

### vault_kv_secret_v2.legacy

**State addresses:**
- v1.x: `vault_kv_secret_v2.legacy`
- v2.0: `vault_kv_secret_v2.legacy[0]`

**Attributes:**
- `data_json` - used in legacy mode (`use_ephemeral_key = false`)
- `data_json_wo` - used in ephemeral mode (`use_ephemeral_key = true`)
- `data_json_wo_version` - tracks `secret_version` for rotation

**Migration:**

This resource adapts automatically based on `use_ephemeral_key`:
- Legacy: reads from `tls_private_key.legacy[0].private_key_pem` → writes to `data_json`
- Ephemeral: reads from `ephemeral.tls_private_key.ephemeral[0].private_key_pem` → writes to `data_json_wo`

---

## Testing Your Upgrade

### Legacy Mode Test
```bash
terraform plan -var="use_ephemeral_key=false"
# Should show only 'moved' operations, no changes
terraform apply -var="use_ephemeral_key=false"
terraform state list | grep legacy  # Should see legacy[0] addresses
```

### Ephemeral Mode Test
```bash
terraform plan -var="use_ephemeral_key=true"
# Should show secret regeneration
terraform apply -var="use_ephemeral_key=true"
terraform state pull | grep -i private_key  # Should show minimal sensitive data
```

### Rotation Test (Ephemeral)
```bash
terraform apply -var="use_ephemeral_key=true" -var="secret_version=2"
# Should regenerate secrets
```

---

## Rollback Procedure

If issues arise:

1. **Restore state:**
   ```bash
   terraform state push tfstate-v1.backup
   ```

2. **Revert version:**
   ```hcl
   version = "~> 1.0"
   ```

3. **Apply:**
   ```bash
   terraform apply
   ```

---

## FAQ

**Q: Will my secrets change?**
- Path 1 (legacy): No
- Path 2 (ephemeral): Yes

**Q: Can I switch back to legacy after going ephemeral?**
- Yes, set `use_ephemeral_key = false`, but secrets regenerate

**Q: How do I rotate ephemeral secrets?**
- Increment `secret_version` variable

**Q: What if I forget to set `use_ephemeral_key = false`?**
- Secrets regenerate on first apply

**Q: Any infrastructure changes?**
- No infrastructure changes, only secret regeneration

---

## Need Help?

- Review [MIGRATION-SUMMARY.md](./MIGRATION-SUMMARY.md)
- Check module documentation
- Open issue for support

---

## Previous Upgrade Guides

- [v1.0 Initial Release](./UPGRADE-GUIDE-1.0.md)
