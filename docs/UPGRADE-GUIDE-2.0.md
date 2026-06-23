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
  - v2.0 (legacy): `tls_private_key.legacy_resource[0]`
  - v2.0 (ephemeral): `ephemeral.tls_private_key.ephemeral[0]`
  
- **vault_kv_secret_v2.legacy**
  - v1.x: `vault_kv_secret_v2.legacy`
  - v2.0: `vault_kv_secret_v2.secret[0]`

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
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
}
```

**After (v2.0):**
```hcl
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
  
  # Opt-out of ephemeral mode
  use_ephemeral_key = false
}
```

**Steps:**
1. Update module source to v2.0
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
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
}
```

**After (v2.0):**
```hcl
module "tls" {
  source = "./terraform-tls-ephemeral-migrator"
  
  # Ephemeral mode is now default
  # use_ephemeral_key = true  # optional explicit
}
```

**Steps:**

1. **Backup state:**
   ```bash
   terraform state pull > tfstate-v1.backup
   ```

2. **Update module version:**
   ```hcl
   source = "./terraform-tls-ephemeral-migrator"  # v2.0
   ```

3. **Plan upgrade:**
   ```bash
   terraform plan
   ```
   
   Expected output:
   - `moved` operations for state address changes
   - Destroy `tls_private_key.legacy_resource[0]` (legacy mode count=0)
   - Create `ephemeral.tls_private_key.ephemeral[0]` (ephemeral mode count=1)
   - **Secrets will regenerate**

4. **Apply upgrade:**
   ```bash
   terraform apply
   ```

5. **Verify state cleaned:**
   ```bash
   terraform state pull | grep -iE "private_key"
   ```
   
   Should show minimal/no sensitive values.

**Result:** Secrets removed from state, ephemeral mode active.

---

### Path 3: Staged Migration (Lower Risk)

Migrate with controlled steps.

1. **Upgrade with legacy mode:**
   ```hcl
   source = "./terraform-tls-ephemeral-migrator"  # v2.0
   use_ephemeral_key = false
   ```

2. **Verify no changes:**
   ```bash
   terraform plan  # Should show only 'moved' operations
   terraform apply
   ```

3. **Switch to ephemeral:**
   ```hcl
   use_ephemeral_key = true
   ```
   
   Apply, verify, update external systems.

---

## Resource-Specific Migration

### tls_private_key

**Toggle:** `use_ephemeral_key`

**State addresses:**
- v1.x: `tls_private_key.legacy`
- v2.0 (legacy, `use_ephemeral_key = false`): `tls_private_key.legacy_resource[0]`
- v2.0 (ephemeral, `use_ephemeral_key = true`): `ephemeral.tls_private_key.ephemeral[0]`

**Consumers:**
- `vault_kv_secret_v2.secret[0].data_json` (legacy mode)
- `vault_kv_secret_v2.secret[0].data_json_wo` (ephemeral mode)

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

### vault_kv_secret_v2

**Write-only attributes available:**
- `data_json_wo` - replaces `data_json` in ephemeral mode

**State addresses:**
- v1.x: `vault_kv_secret_v2.legacy`
- v2.0: `vault_kv_secret_v2.secret[0]`

---

## Testing Your Upgrade

### Legacy Mode Test
```bash
terraform plan  # Should show only 'moved' operations, no changes
terraform apply
terraform state list | grep legacy_resource  # Should see legacy_resource[0] address
```

### Ephemeral Mode Test
```bash
terraform plan  # Should show secret regeneration
terraform apply
terraform state pull | grep -i private_key  # Should show minimal sensitive data
```

### Rotation Test (Ephemeral)
```hcl
secret_version = 2
```
```bash
terraform apply  # Should regenerate secrets
```

---

## Rollback Procedure

If issues arise:

1. **Restore state:**
   ```bash
   terraform state push tfstate-v1.backup
   ```

2. **Revert version:**
   Update module source back to v1.x

3. **Apply:**
   ```bash
   terraform apply
   ```

---

## FAQ

**Q: Will my secrets change?**
- Path 1 (legacy): No
- Path 2 (ephemeral): Yes
- Path 3 (staged): Yes, per secret type

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

- Review [Upgrade Procedures](./skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md)
- Check [v1.1 Migration Guide](./UPGRADE-GUIDE-1.1.md)
- Open issue for support

---

## Previous Upgrade Guides

- [v1.0 Initial Release](../README.md)
- [v1.1 Add Ephemeral Support](./UPGRADE-GUIDE-1.1.md)
