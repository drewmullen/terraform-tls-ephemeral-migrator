# Upgrade from v1.0 to v2.0

This major version changes the default behavior for secret handling. Secrets are now **stored as ephemeral values by default** and never persisted to state. This improves security but requires migration for existing deployments.

## What Changed

### Default Behavior
- `use_ephemeral_key` variable now defaults to `true` (was `false`)
- TLS private keys no longer stored in Terraform state by default
- Existing users must explicitly opt-out to maintain legacy behavior

### Resources Affected

- **tls_private_key.legacy**
  - v1.x: `tls_private_key.legacy_mode[0]`
  - v2.0 (legacy): `tls_private_key.legacy_mode[0]`
  - v2.0 (ephemeral): `ephemeral.tls_private_key.ephemeral[0]`
  
- **vault_kv_secret_v2.legacy**
  - v1.x: `vault_kv_secret_v2.storage[0]`
  - v2.0: `vault_kv_secret_v2.storage[0]` (uses `data_json_wo` for ephemeral)

### Breaking Changes

- **use_ephemeral_key** variable now defaults to `true`
- Keys regenerated unless explicitly opted-out
- State addresses changed (handled by `moved` blocks)

---

## Upgrade Paths

### Path 1: Maintain Legacy Behavior (No Key Regeneration)

Keep keys in state, avoid regeneration.

**Before (v1.x):**
```hcl
module "tls" {
  source  = "./terraform-tls-ephemeral-migrator"
}
```

**After (v2.0):**
```hcl
module "tls" {
  source  = "./terraform-tls-ephemeral-migrator"
  
  # Opt-out of ephemeral mode
  use_ephemeral_key = false
}
```

**Steps:**
1. Update module source/version
2. Add `use_ephemeral_key = false`
3. Run `terraform plan` - should show:
   - `moved` operations (state address changes)
   - No resource changes
4. Run `terraform apply`

**Result:** Keys remain in state, no regeneration.

---

### Path 2: Migrate to Ephemeral (Recommended)

Adopt ephemeral mode, remove keys from state.

**⚠️ Warning:** This **regenerates TLS private keys**. Update external systems accordingly.

**Before (v1.x):**
```hcl
module "tls" {
  source  = "./terraform-tls-ephemeral-migrator"
}
```

**After (v2.0):**
```hcl
module "tls" {
  source  = "./terraform-tls-ephemeral-migrator"
  
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
   # Update source/version to v2.0
   ```

3. **Plan upgrade:**
   ```bash
   terraform plan
   ```
   
   Expected output:
   - `moved` operations for state address changes
   - Destroy `tls_private_key.legacy_mode[0]` (legacy mode count=0)
   - Create `ephemeral.tls_private_key.ephemeral[0]` (ephemeral mode count=1)
   - Update `vault_kv_secret_v2.storage[0]` (use `data_json_wo`)
   - **Keys will regenerate**

4. **Apply upgrade:**
   ```bash
   terraform apply
   ```

5. **Verify state cleaned:**
   ```bash
   terraform state pull | grep -i private_key
   ```
   
   Should show minimal/no private keys.

**Result:** Keys removed from state, ephemeral mode active.

---

### Path 3: Staged Migration (Lower Risk)

Migrate gradually.

1. **Upgrade with legacy:**
   ```hcl
   use_ephemeral_key = false
   ```

2. **Test thoroughly**, then enable:
   ```hcl
   use_ephemeral_key = true
   ```

3. **Apply**, verify, update external systems.

---

## Resource-Specific Migration

### tls_private_key.legacy

**Toggle:** `use_ephemeral_key`

**State addresses:**
- v1.x: `tls_private_key.legacy_mode[0]`
- v2.0 (legacy, `use_ephemeral_key = false`): `tls_private_key.legacy_mode[0]`
- v2.0 (ephemeral, `use_ephemeral_key = true`): `ephemeral.tls_private_key.ephemeral[0]`

**Consumers:**
- `vault_kv_secret_v2.storage[0].data_json` (legacy mode)
- `vault_kv_secret_v2.storage[0].data_json_wo` (ephemeral mode)

**Migration:**

Legacy mode (v2.0):
```hcl
module "tls" {
  use_ephemeral_key = false
}
```

Ephemeral mode (v2.0 default):
```hcl
module "tls" {
  # Defaults to true
  # use_ephemeral_key = true
}
```

**Rotation (ephemeral mode only):**
```hcl
module "tls" {
  secret_version = 2  # increment to regenerate
}
```

---

## Testing Your Upgrade

### Legacy Mode Test
```bash
terraform plan  # Should show only 'moved' operations, no changes
terraform apply
terraform state list | grep legacy_mode  # Should see legacy_mode[0] address
```

### Ephemeral Mode Test
```bash
terraform plan  # Should show key regeneration
terraform apply
terraform state pull | grep -i private_key  # Should show minimal data
```

### Rotation Test (Ephemeral)
```hcl
secret_version = 2
```
```bash
terraform apply  # Should regenerate keys
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
   # Use v1.x module source
   ```

3. **Apply:**
   ```bash
   terraform apply
   ```

---

## FAQ

**Q: Will my keys change?**
- Path 1 (legacy): No
- Path 2 (ephemeral): Yes

**Q: Can I switch back to legacy after going ephemeral?**
- Yes, set `use_ephemeral_key = false`, but keys regenerate

**Q: How do I rotate ephemeral keys?**
- Increment `secret_version` variable

**Q: What if I forget to set `use_ephemeral_key = false`?**
- Keys regenerate on first apply

**Q: Any infrastructure changes?**
- No infrastructure changes, only key regeneration

---

## Need Help?

- Review [MIGRATION-SUMMARY.md](./MIGRATION-SUMMARY.md)
- Open issue for support
