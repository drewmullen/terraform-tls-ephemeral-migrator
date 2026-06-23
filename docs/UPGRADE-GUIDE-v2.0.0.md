# Upgrade from v1.x to v2.0

This major version changes the default behavior for secret handling. Secrets are now **stored as ephemeral values by default** and never persisted to state. This improves security but requires migration for existing deployments.

## What Changed

### Default Behavior
- `use_ephemeral_key` now defaults to `true` (was `false`)
- TLS private key no longer stored in Terraform state by default
- Existing users must explicitly opt-out to maintain legacy behavior

### Resources Affected

- **tls_private_key.legacy**
  - v1.x: `tls_private_key.legacy`
  - v2.0 (legacy mode): `tls_private_key.legacy[0]`
  - v2.0 (ephemeral mode): `ephemeral.tls_private_key.ephemeral[0]`

- **vault_kv_secret_v2.legacy**
  - v1.x: stored private key in `data_json` (state-persisted)
  - v2.0 (legacy mode): same, `data_json` with `one()` pattern
  - v2.0 (ephemeral mode): `data_json_wo` write-only (never read back)

### Breaking Changes

- `use_ephemeral_key` now defaults to `true`
- Private key regenerated unless explicitly opted-out
- State address changed (handled by `moved` block)

---

## Upgrade Paths

### Path 1: Maintain Legacy Behavior (No Key Regeneration)

Keep the private key in state, avoid regeneration.

**Before (v1.x):**
```hcl
module "example" {
  source  = "..."
  version = "~> 1.0"
}
```

**After (v2.0):**
```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"

  # Opt-out of ephemeral mode
  use_ephemeral_key = false
}
```

**Steps:**
1. Update `version = "~> 2.0"`
2. Add `use_ephemeral_key = false`
3. Run `terraform plan` — should show:
   - `moved` operations (state address changes)
   - In-place update on `vault_kv_secret_v2.legacy` (data_json expression updated, no value change)
   - No resource creates or destroys
4. Run `terraform apply`

**Result:** Private key remains in state, no regeneration.

---

### Path 2: Migrate to Ephemeral (Recommended)

Adopt ephemeral mode, remove private key from state.

**⚠️ Warning:** This **regenerates the TLS private key**. Update any systems consuming the certificate/key accordingly.

**Before (v1.x):**
```hcl
module "example" {
  source  = "..."
  version = "~> 1.0"
}
```

**After (v2.0):**
```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"

  # Ephemeral mode is now default — explicit setting optional
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
   - Destroy `tls_private_key.legacy[0]` (legacy count=0)
   - Create `ephemeral.tls_private_key.ephemeral[0]` (ephemeral count=1)
   - Update `vault_kv_secret_v2.legacy` (switch from `data_json` to `data_json_wo`)
   - **Private key will regenerate**

4. **Apply upgrade:**
   ```bash
   terraform apply
   ```

5. **Verify state cleaned:**
   ```bash
   terraform state pull | grep -iE "private_key"
   ```

   Should show minimal/no sensitive values.

**Result:** Private key removed from state, ephemeral mode active.

---

### Path 3: Staged Migration (Lower Risk)

Upgrade cleanly first, then switch to ephemeral separately.

1. **Upgrade with legacy mode:**
   ```hcl
   version = "~> 2.0"
   use_ephemeral_key = false
   ```
   Apply, verify no changes beyond `moved` blocks.

2. **Switch to ephemeral:**
   ```hcl
   use_ephemeral_key = true  # or remove — now the default
   ```
   Apply. Private key regenerates.

3. **Update downstream systems** with new key/certificate values.

---

## Resource-Specific Migration

### tls_private_key.legacy

**Toggle:** `use_ephemeral_key`

**State addresses:**
- v1.x: `tls_private_key.legacy`
- v2.0 (legacy, `use_ephemeral_key = false`): `tls_private_key.legacy[0]`
- v2.0 (ephemeral, `use_ephemeral_key = true`): `ephemeral.tls_private_key.ephemeral[0]`

**Consumer:**
- `vault_kv_secret_v2.legacy.data_json` (legacy mode)
- `vault_kv_secret_v2.legacy.data_json_wo` (ephemeral mode)

**Rotation (ephemeral mode only):**
```hcl
module "example" {
  secret_version = 2  # increment to regenerate key
}
```

---

## Testing Your Upgrade

### Legacy Mode Test
```bash
terraform plan  # Should show only 'moved' operations and in-place data_json update
terraform apply
terraform state list | grep legacy  # Should see legacy[0] addresses
```

### Ephemeral Mode Test
```bash
terraform plan  # Should show key regeneration
terraform apply
terraform state pull | grep -i private_key  # Should show no sensitive data
```

### Rotation Test (Ephemeral)
```hcl
secret_version = 2
```
```bash
terraform apply  # Should regenerate key and re-write to Vault
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
   version = "~> 1.1"
   ```

3. **Apply:**
   ```bash
   terraform apply
   ```

---

## FAQ

**Q: Will my private key change?**
- Path 1 (legacy): No
- Path 2 (ephemeral): Yes
- Path 3 (staged): Yes, when switching to ephemeral

**Q: Can I switch back to legacy after going ephemeral?**
- Yes, set `use_ephemeral_key = false`, but a new key will be generated

**Q: How do I rotate the ephemeral key?**
- Increment `secret_version` variable

**Q: What if I forget to set `use_ephemeral_key = false`?**
- Key regenerates on first apply after v2.0 upgrade

**Q: Any infrastructure changes?**
- No infrastructure changes, only key regeneration and Vault secret update

---

## Need Help?

- Review [docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md](./skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) for step-by-step upgrade procedures
- Check [examples/](../examples/)
- Open issue for support

---

## Previous Upgrade Guides

- v1.0 Initial Release (no upgrade guide — first version)
