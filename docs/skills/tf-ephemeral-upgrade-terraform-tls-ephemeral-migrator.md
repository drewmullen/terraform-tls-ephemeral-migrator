---
name: tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator
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
grep -rn 'module "terraform-tls-ephemeral-migrator"' . --include="*.tf"
```

Or use Terraform CLI:

```bash
terraform state list | grep 'module\.terraform-tls-ephemeral-migrator'
```

Record:
- Module call name
- Module source
- Current version (if pinned)

## Step 2: Extract Secret Values from State

**⚠️ Important:** Only extract if user wants to preserve current secret values during migration. If regenerating secrets is acceptable, skip to Step 3.

### Extract Commands by Resource Type

#### tls_private_key

Extract private key from state:

```bash
# Get resource address
terraform state list | grep 'tls_private_key'

# Show resource
terraform state show 'tls_private_key.legacy'

# Extract private key (save to secure location)
terraform state pull | jq -r '
  .resources[] 
  | select(.type == "tls_private_key") 
  | .instances[0].attributes.private_key_pem
' > private_key.pem.tmp
```

**Security:** Store extracted secrets securely (Vault, AWS Secrets Manager, 1Password, etc). Delete temporary files after migration.

#### vault_kv_secret_v2 (resource)

Extract secret data from state:

```bash
terraform state pull | jq -r '
  .resources[]
  | select(.type == "vault_kv_secret_v2" and .mode == "managed")
  | .instances[0].attributes.data_json
' > vault_data.json.tmp
```

### Alternative: Use Terraform Outputs

If module exposes non-sensitive outputs referencing secrets:

```bash
terraform output -json | jq '.terraform_tls_ephemeral_migrator_<output>.value'
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

### Option B: Use Extracted Secrets (Ephemeral Mode)

If migrating to ephemeral but want to inject existing secrets:

**Note:** This is complex and not recommended. Ephemeral resources are meant to generate new values. If you need to preserve exact secret values, use Option A (legacy mode) or manually recreate secrets in external system before migration.

### Option C: Regenerate Secrets (Ephemeral Mode - Recommended)

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

### Update Module Source

This is a standalone module (not in registry). Update local path or git source:

**Legacy Mode (Option A):**
```hcl
module "tls_example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  # Preserve existing secrets
  use_ephemeral_key = false
}
```

**Ephemeral Mode (Option C - Recommended):**
```hcl
module "tls_example" {
  source = "./terraform-tls-ephemeral-migrator"
  
  # Ephemeral mode is default in v2.0
  # Optionally explicit:
  # use_ephemeral_key = true
}
```

### Initialize Upgrade

```bash
terraform init -upgrade
```

## Step 5: Validate Upgrade

### Plan Upgrade

```bash
terraform plan -out=upgrade.tfplan
```

### Expected Output: Legacy Mode

```
# tls_private_key.legacy has moved to tls_private_key.legacy[0]
  resource "tls_private_key" "legacy" {
      # (no changes)
  }

# vault_kv_secret_v2.legacy has moved to vault_kv_secret_v2.legacy[0]
  resource "vault_kv_secret_v2" "legacy" {
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
# tls_private_key.legacy[0] will be destroyed
# (due to moved and count=0 in ephemeral mode)

# ephemeral.tls_private_key.ephemeral[0] will be created
+ ephemeral "tls_private_key" "ephemeral" {
    + algorithm = "RSA"
    + rsa_bits  = 4096
    # ...
  }

# vault_kv_secret_v2.legacy[0] will be updated in-place
~ resource "vault_kv_secret_v2" "legacy" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
    + data_json_wo_version = 1
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
terraform state list | grep -E "(legacy|ephemeral)"
```

Legacy mode should show:
```
tls_private_key.legacy[0]
vault_kv_secret_v2.legacy[0]
```

Ephemeral mode should show:
```
ephemeral.tls_private_key.ephemeral[0]
vault_kv_secret_v2.legacy[0]
```

**Verify secrets removed from state (ephemeral mode):**
```bash
terraform state pull | grep -iE "private_key_pem" | wc -l
# Should be 0 or minimal
```

## Step 6: Update Downstream Systems

**Ephemeral mode only:** Secrets regenerated, update consuming systems.

### Get New Secret Values

Retrieve from Vault where module writes secrets:

```bash
vault kv get -format=json kvv2/mytls | jq -r '.data.data.private_key'
```

### Update Consumers

- Applications reading secrets from Vault
- Services using TLS certificates
- Systems depending on this private key

**Rotation workflow:**
1. Get new secret values from Vault
2. Update consuming systems
3. Verify connectivity/functionality
4. Decommission old secrets (if they exist outside Terraform)

## Rollback Procedure

If issues arise:

```bash
# Restore state
terraform state push tfstate-before-upgrade-<timestamp>.backup

# Revert module configuration
# (restore old source path or variable values)

# Re-initialize
terraform init -upgrade

# Verify rollback
terraform plan  # Should show no changes
```

## Secret Rotation (Ephemeral Mode)

After upgrade, rotate secrets by incrementing version:

```hcl
module "tls_example" {
  source = "./terraform-tls-ephemeral-migrator"
  
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
- Verify module uses `data_json_wo` for ephemeral path
- Check `use_ephemeral_key` variable is set correctly

### "Invalid index" on resource[0]

**Error:**
```
Error: Invalid index
  The given key does not identify an element
```

**Cause:** Module referencing resource with count=0.

**Fix:** Module should use `one(resource[*].attr)` pattern. Check module code or report bug.

### Unexpected resource changes

**Issue:** Plan shows infrastructure changes (not just secrets).

**Fix:**
1. Do NOT apply
2. Review UPGRADE-GUIDE-2.0.md for known issues
3. Verify variable syntax
4. Report issue if persists

### Secrets not removed from state

**Issue:** After ephemeral upgrade, state still has sensitive values.

**Fix:**
- Verify `use_ephemeral_key = true` (or removed for default)
- Run `terraform refresh` and re-check state

## Commands Reference

```bash
# Backup state
terraform state pull > state.backup

# Detect module usage
terraform state list | grep 'tls_private_key\|vault_kv_secret'

# Extract secret (example)
terraform state pull | jq '.resources[] | select(.type == "tls_private_key")'

# Plan upgrade
terraform plan -out=upgrade.tfplan

# Apply upgrade
terraform apply upgrade.tfplan

# Verify state
terraform state list | grep -E "(legacy|ephemeral)"

# Check for secrets in state
terraform state pull | grep -iE "private_key_pem" | wc -l

# Rollback
terraform state push state.backup
```

## FAQ

**Q: Should I use legacy or ephemeral mode?**
- **Ephemeral recommended** for better security
- Use legacy if you cannot regenerate secrets

**Q: How do I preserve exact secret values?**
- Use legacy mode (`use_ephemeral_key = false`)
- Or manually recreate secrets in Vault before migration

**Q: Can I upgrade without downtime?**
- Legacy mode: yes, no changes
- Ephemeral mode: depends on downstream systems' tolerance for secret rotation

**Q: What if I need to rollback?**
- Restore state backup, revert configuration, reinitialize

**Q: How often should I rotate ephemeral secrets?**
- Recommended: increment `secret_version` quarterly or after suspected compromise

## Related Documentation

- [UPGRADE-GUIDE-2.0.md](./UPGRADE-GUIDE-2.0.md) - Full upgrade guide
- [MIGRATION-SUMMARY.md](./MIGRATION-SUMMARY.md) - Technical migration details
