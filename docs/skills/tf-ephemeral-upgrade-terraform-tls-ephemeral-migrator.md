---
name: tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator
description: >
  Assist with upgrading terraform-tls-ephemeral-migrator from v1.x to v2.0 (ephemeral defaults).
  Handles secret extraction from state, writing secrets as workspace variables via API,
  version pinning, and validation. Prefers v2.0 ephemeral mode and preserves secret values.
  Use when upgrading this module to remove secrets from state.
---

# terraform-tls-ephemeral-migrator Ephemeral Upgrade Assistant

Upgrade terraform-tls-ephemeral-migrator from v1.x → v2.0. Secrets preserved by extracting from
state and writing to HCP Terraform workspace variables via API before switching to ephemeral mode.

## Workflow

1. Detect module usage in workspace
2. Extract current secret values from state
3. Write secret values to HCP Terraform workspace variables via API
4. Upgrade module version to v2.0
5. Validate upgrade

## Prerequisites

- Terraform v1.11+ (ephemeral support)
- HCP Terraform workspace with API access
- `curl` and `jq` installed
- HCP Terraform API token

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
- Workspace ID (from HCP Terraform UI or `terraform workspace show`)

## Step 2: Extract Secret Values from State

Extract the TLS private key before migration to preserve it.

### tls_private_key.legacy → tls_private_key.legacy[0]

```bash
terraform state pull | jq -r '
  .resources[]
  | select(.type == "tls_private_key" and .name == "legacy")
  | .instances[0].attributes.private_key_pem
'
```

**Security:** Keep extracted values in memory or a secure secrets manager. Do not write to disk unencrypted.

## Step 3: Write Secrets to Workspace Variables via API

Write extracted secret values as sensitive workspace variables in HCP Terraform.

**Set your workspace details:**
```bash
TFC_TOKEN="<your-api-token>"
WORKSPACE_ID="<your-workspace-id>"   # e.g. ws-abc123
TFC_API="https://app.terraform.io/api/v2"
```

**Write the private key as a workspace variable:**

```bash
curl -s \
  --request POST \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data '{
    "data": {
      "type": "vars",
      "attributes": {
        "key": "tls_private_key_pem",
        "value": "<extracted_private_key_pem>",
        "category": "terraform",
        "sensitive": true,
        "description": "Preserved TLS private key migrated from state"
      }
    }
  }' \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars"
```

**Verify variable was created:**
```bash
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | jq '.data[] | {name: .attributes.key, sensitive: .attributes.sensitive}'
```

The variable should appear with `"sensitive": true`. Value will not be shown.

## Step 4: Upgrade Module Version

### Backup State First

```bash
terraform state pull > tfstate-before-upgrade-$(date +%Y%m%d-%H%M%S).backup
```

### Update Module Version

Locate module block:

```hcl
module "terraform-tls-ephemeral-migrator" {
  source  = "..."
  version = "~> 1.1"  # old version
}
```

Update to v2.0:

```hcl
module "terraform-tls-ephemeral-migrator" {
  source  = "..."
  version = "~> 2.0"  # upgraded
}
```

### Initialize Upgrade

```bash
terraform init -upgrade
```

Expected output:
```
Upgrading modules...
- terraform-tls-ephemeral-migrator in ...
  Downloading <source> 2.0.0 for terraform-tls-ephemeral-migrator...
```

## Step 5: Validate Upgrade

### Plan Upgrade

```bash
terraform plan -out=upgrade.tfplan
```

### Expected Output

```
# module.terraform-tls-ephemeral-migrator.tls_private_key.legacy has moved to
# module.terraform-tls-ephemeral-migrator.tls_private_key.legacy[0]
  resource "tls_private_key" "legacy" {
      # (no changes)
  }

# module.terraform-tls-ephemeral-migrator.vault_kv_secret_v2.legacy will be updated in-place
~ resource "vault_kv_secret_v2" "legacy" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
  }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Validation:**
- ✅ Only `moved` operations and write-only attribute updates
- ✅ No resource creates or destroys
- ✅ No infrastructure changes

### Review Plan Carefully

If the plan shows unexpected resource creates or destroys → **Do NOT apply**. Review troubleshooting section below.

### Apply Upgrade

```bash
terraform apply upgrade.tfplan
```

## Rollback Procedure

If issues arise:

```bash
# Restore state
terraform state push tfstate-before-upgrade-<timestamp>.backup

# Revert module version in config
# version = "~> 1.1"

# Re-initialize
terraform init -upgrade

# Verify rollback
terraform plan  # Should show no changes
```

## Troubleshooting

### "Ephemeral values not valid for attribute"

**Error:**
```
Error: Invalid use of ephemeral value
  Ephemeral values are not valid for "data_json"
```

**Fix:**
- Verify module version is v2.0+
- Check module uses `data_json_wo` for ephemeral path

### "Invalid index" on resource[0]

**Error:**
```
Error: Invalid index
  The given key does not identify an element
```

**Fix:** Module uses `one(resource[*].attr)` pattern. If this error appears, report bug to module maintainer.

### Unexpected resource creates or destroys

**Issue:** Plan shows infrastructure additions or deletions.

**Fix:**
1. Do NOT apply
2. Review [UPGRADE-GUIDE-v2.0.0.md](../UPGRADE-GUIDE-v2.0.0.md) for known issues
3. Verify module version is correct
4. Report issue if persists

## Commands Reference

```bash
# Backup state
terraform state pull > state.backup

# Detect module usage
terraform state list | grep 'module\.terraform-tls-ephemeral-migrator'

# Extract TLS private key
terraform state pull | jq -r '.resources[] | select(.type == "tls_private_key" and .name == "legacy") | .instances[0].attributes.private_key_pem'

# Write workspace variable
curl -s --request POST \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data '{"data":{"type":"vars","attributes":{"key":"tls_private_key_pem","value":"<value>","category":"terraform","sensitive":true}}}' \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars"

# List workspace variables
curl -s --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | jq '.data[] | {name: .attributes.key, sensitive: .attributes.sensitive}'

# Upgrade module
terraform init -upgrade

# Plan upgrade
terraform plan -out=upgrade.tfplan

# Apply upgrade
terraform apply upgrade.tfplan

# Rollback
terraform state push state.backup
```

## FAQ

**Q: Why write secrets as workspace variables?**
- Secrets preserved from current state without exposure to disk
- Sensitive variables never shown in HCP Terraform UI or logs
- Module can reference via `var.<name>` input

**Q: What if I don't have the workspace ID?**
- HCP Terraform UI: Settings → General → ID field
- Or: `curl -H "Authorization: Bearer $TFC_TOKEN" "https://app.terraform.io/api/v2/organizations/<org>/workspaces/<name>" | jq '.data.id'`

**Q: What if I need to rollback?**
- Restore state backup, revert version, reinitialize

**Q: Can I upgrade without downtime?**
- Yes — `moved` blocks ensure no resource destroy/create

**Q: What if I don't use HCP Terraform?**
- Extract the private key value from state and store it in your preferred secrets manager
- Pass the value as a module input variable instead of using workspace variables

## Related Documentation

- [UPGRADE-GUIDE-v2.0.0.md](../UPGRADE-GUIDE-v2.0.0.md) - Full upgrade guide
- [examples/](../../examples/) - Reference implementations
