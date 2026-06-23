---
name: tf-ephemeral-upgrade-tls-migrator
description: >
  Assist with upgrading terraform-tls-ephemeral-migrator from v1.x to v2.0 (ephemeral defaults).
  Handles secret extraction from state, variable creation, version pinning, and validation.
  Prefers v2.0 ephemeral mode but supports legacy fallback. Use when upgrading this module
  to remove secrets from state.
---

# terraform-tls-ephemeral-migrator Ephemeral Upgrade Assistant

Upgrade terraform-tls-ephemeral-migrator from v1.x → v2.0 with ephemeral secrets.

## Workflow

1. Detect module usage in workspace
2. Extract current secret values from state
3. Create/update variables for ephemeral mode
4. Upgrade module version to v2.0
5. Validate upgrade

## Prerequisites

- Terraform v1.11+ (ephemeral support)
- Access to current state file
- Permissions to modify Terraform config

## Step 1: Detect Module Usage

Scan workspace for module calls:

```bash
grep -rn 'module.*terraform-tls-ephemeral-migrator' . --include="*.tf"
```

Or use Terraform CLI:

```bash
terraform state list | grep 'module\.'
```

Record:
- Module call name
- Module source
- Current version (if pinned)

## Step 2: Extract Secret Values from State

**⚠️ Important:** Only extract if user wants to preserve current secret values during migration. If regenerating secrets is acceptable, skip to Step 3.

### Extract TLS Private Key

Extract private key from state:

```bash
# Get resource address
terraform state list | grep 'tls_private_key'

# Show resource
terraform state show 'module.<module-name>.tls_private_key.legacy_mode[0]'

# Extract private key (save to secure location)
terraform state pull | jq -r '
  .resources[] 
  | select(.module == "module.<module-name>" and .type == "tls_private_key") 
  | .instances[0].attributes.private_key_pem
' > private_key.pem.tmp
```

**Security:** Store extracted secrets securely (Vault, AWS Secrets Manager, 1Password, etc). Delete temporary files after migration.

### Alternative: Use Terraform Outputs

If module exposes non-sensitive outputs referencing secrets:

```bash
terraform output -json | jq '.module_<module-name>_<output>.value'
```

**Note:** Most ephemeral migrations won't expose secrets via outputs.

## Step 3: Create/Update Variables

### Option A: Keep Current Secrets (Legacy Mode)

If preserving current secrets (no regeneration):

**Create variables file** (`terraform.tfvars` or workspace variables):

```hcl
# Force legacy mode to prevent regeneration
use_ephemeral_key = false
```

No secret variables needed - existing state values preserved.

### Option B: Regenerate Secrets (Ephemeral Mode - Recommended)

Accept secret regeneration, no variables needed:

```hcl
# Module defaults to ephemeral mode in v2.0
# No variables needed unless customizing
```

Prepare to update downstream systems with new secret values after apply.

## Step 4: Upgrade Module Version

### Backup State First

```bash
terraform state pull > tfstate-before-upgrade-$(date +%Y%m%d-%H%M%S).backup
```

### Update Module Version

Locate module block:

```hcl
module "tls" {
  source  = "..."
  
  # ... existing config
}
```

Update to v2.0 and add mode selection:

**Legacy Mode (Option A):**
```hcl
module "tls" {
  source  = "..."
  
  # Preserve existing secrets
  use_ephemeral_key = false
  
  # ... existing config
}
```

**Ephemeral Mode (Recommended):**
```hcl
module "tls" {
  source  = "..."
  
  # Ephemeral mode is default in v2.0
  # Optionally explicit:
  # use_ephemeral_key = true
  
  # ... existing config
}
```

### Initialize Upgrade

```bash
terraform init -upgrade
```

Expected output:
```
Upgrading modules...
- tls in ...
  Downloading <source> for tls...
```

## Step 5: Validate Upgrade

### Plan Upgrade

```bash
terraform plan -out=upgrade.tfplan
```

### Expected Output: Legacy Mode

```
# module.tls.tls_private_key.legacy has moved to module.tls.tls_private_key.legacy_mode[0]
  resource "tls_private_key" "legacy_mode" {
      # (no changes)
  }

Plan: 0 to add, 0 to change, 0 to destroy.
```

**Validation:**
- ✅ Only `moved` operations
- ✅ No resource changes
- ✅ No destroys

### Expected Output: Ephemeral Mode

```
# module.tls.tls_private_key.legacy_mode[0] will be destroyed
# (due to count = 0)

# module.tls.ephemeral.tls_private_key.ephemeral[0] will be created
+ ephemeral "tls_private_key" "ephemeral" {
    + algorithm = "RSA"
    + rsa_bits  = 4096
    # ...
  }

# module.tls.vault_kv_secret_v2.storage[0] will be updated in-place
~ resource "vault_kv_secret_v2" "storage" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
    # ...
  }

Plan: X to add, Y to change, Z to destroy.
```

**Validation:**
- ✅ Destroy old resources (legacy mode count=0)
- ✅ Create ephemeral resources
- ✅ Update consumers to use write-only attributes
- ⚠️ Secrets will regenerate

### Review Plan Carefully

Check for unexpected changes:
- Infrastructure changes (VMs, databases, etc) → ❌ Should not happen
- Only secret regeneration → ✅ Expected in ephemeral mode

### Apply Upgrade

**Legacy mode:**
```bash
terraform apply upgrade.tfplan
# Should complete immediately
```

**Ephemeral mode:**
```bash
terraform apply upgrade.tfplan
# Regenerates secrets
```

### Post-Apply Validation

**Verify state addresses:**
```bash
terraform state list | grep -E "(legacy_mode|ephemeral)"
```

Legacy mode should show:
```
module.tls.tls_private_key.legacy_mode[0]
```

Ephemeral mode should show:
```
module.tls.ephemeral.tls_private_key.ephemeral[0]
```

**Verify secrets removed from state (ephemeral mode):**
```bash
terraform state pull | grep -i private_key | wc -l
# Should be significantly reduced
```

**Test outputs:**
```bash
terraform output
# Verify downstream systems can access new secrets
```

## Step 6: Update Downstream Systems

**Ephemeral mode only:** Secrets regenerated, update consuming systems.

### Get New Secret Values

Module should expose outputs (non-sensitive metadata only) or secrets are in Vault:

```bash
# If module writes to Vault
vault kv get kvv2/mytls
```

### Update Consumers

- Applications reading secrets from Vault
- Services using TLS certificates
- CI/CD systems with credentials

**Rotation workflow:**
1. Get new secret values
2. Update consuming systems
3. Verify connectivity/functionality
4. Decommission old secrets (if they exist outside Terraform)

## Rollback Procedure

If issues arise:

```bash
# Restore state
terraform state push tfstate-before-upgrade-<timestamp>.backup

# Revert module version in config
# (remove version pin or revert to v1.x)

# Re-initialize
terraform init -upgrade

# Verify rollback
terraform plan  # Should show no changes
```

## Secret Rotation (Ephemeral Mode)

After upgrade, rotate secrets by incrementing version:

```hcl
module "tls" {
  source = "..."
  
  secret_version = 2  # Increment to rotate
}
```

```bash
terraform apply
# Regenerates all ephemeral secrets
```

## Troubleshooting

### "Ephemeral values not valid for attribute"

**Error:**
```
Error: Invalid use of ephemeral value
  Ephemeral values are not valid for "data_json"
```

**Cause:** Module not fully migrated or using old version.

**Fix:**
- Verify module version is v2.0+
- Check module uses `data_json_wo` for ephemeral path

### "Invalid index" on resource[0]

**Error:**
```
Error: Invalid index
  The given key does not identify an element
```

**Cause:** Module referencing resource with count=0.

**Fix:** Module should use `one(resource[*].attr)` pattern. Report bug to module maintainer.

### Unexpected resource changes

**Issue:** Plan shows infrastructure changes (not just secrets).

**Fix:**
1. Do NOT apply
2. Review UPGRADE-GUIDE-2.0.md for known issues
3. Check module version is correct
4. Verify variable syntax
5. Report issue if persists

### Secrets not removed from state

**Issue:** After ephemeral upgrade, state still has sensitive values.

**Fix:**
- Verify `use_ephemeral_key = true` (or removed for default)
- Check module version v2.0+
- Run `terraform refresh` and re-check state

## Commands Reference

```bash
# Backup state
terraform state pull > state.backup

# Detect module usage
terraform state list | grep 'module\.'

# Extract secret (example)
terraform state pull | jq '.resources[] | select(.type == "tls_private_key")'

# Upgrade module
terraform init -upgrade

# Plan upgrade
terraform plan -out=upgrade.tfplan

# Apply upgrade
terraform apply upgrade.tfplan

# Verify state
terraform state list | grep -E "(legacy_mode|ephemeral)"

# Check for secrets in state
terraform state pull | grep -i private_key | wc -l

# Rollback
terraform state push state.backup
```

## FAQ

**Q: Should I use legacy or ephemeral mode?**
- **Ephemeral recommended** for better security
- Use legacy if you cannot regenerate secrets

**Q: How do I preserve exact secret values?**
- Use legacy mode (`use_ephemeral_key = false`)
- Or manually recreate secrets in external system before migration

**Q: Can I upgrade without downtime?**
- Legacy mode: yes, no changes
- Ephemeral mode: depends on downstream systems' tolerance for secret rotation

**Q: What if I need to rollback?**
- Restore state backup, revert version, reinitialize

**Q: How often should I rotate ephemeral secrets?**
- Recommended: increment `secret_version` quarterly or after suspected compromise

## Related Documentation

- [UPGRADE-GUIDE-2.0.md](../../UPGRADE-GUIDE-2.0.md) - Full upgrade guide
- [MIGRATION-SUMMARY.md](../../MIGRATION-SUMMARY.md) - Technical migration details
