---
name: tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator
description: >
  Assist with upgrading terraform-tls-ephemeral-migrator from v1.x to v2.0 (ephemeral defaults).
  Handles secret extraction from state, writing secrets as workspace variables via API,
  version pinning, and validation. Prefers v2.0 ephemeral mode and preserves secret values.
  Use when upgrading this module to remove secrets from state.
---

# terraform-tls-ephemeral-migrator Ephemeral Upgrade Assistant

Upgrade terraform-tls-ephemeral-migrator from v1.x → v2.0. Secrets preserved by extracting from state and
writing to HCP Terraform workspace variables via API before switching to ephemeral mode.

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
grep -rn 'module "tls_migrator"' . --include="*.tf"
```

Or use Terraform CLI:

```bash
terraform state list | grep 'tls_private_key\|vault_kv_secret'
```

Record:
- Module call name (or root module if not a module)
- Current version (if pinned)
- Workspace ID (from HCP Terraform UI or `terraform workspace show`)

## Step 2: Extract Secret Values from State

Extract current secret values before migration to preserve them.

### tls_private_key

```bash
terraform state pull | jq -r '
  .resources[]
  | select(.type == "tls_private_key")
  | .instances[0].attributes.private_key_pem
'
```

### vault_kv_secret_v2 (data stored)

```bash
terraform state pull | jq -r '
  .resources[]
  | select(.type == "vault_kv_secret_v2")
  | .instances[0].attributes.data_json
'
```

**Security:** Keep extracted values in memory or a secure secrets manager. Do not write to disk unencrypted.

## Step 3: Write Secrets to Workspace Variables via API

Write extracted secret values as sensitive workspace variables in HCP Terraform.
This allows the module to consume them as `var.<name>` inputs rather than generating new values.

**Set your workspace details:**
```bash
TFC_TOKEN="<your-api-token>"
WORKSPACE_ID="<your-workspace-id>"   # e.g. ws-abc123
TFC_API="https://app.terraform.io/api/v2"
```

**Write each secret as a workspace variable:**

```bash
# Example: write a private key value
curl -s \
  --request POST \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data '{
    "data": {
      "type": "vars",
      "attributes": {
        "key": "tls_private_key_pem",
        "value": "<extracted_value>",
        "category": "terraform",
        "sensitive": true,
        "description": "Preserved TLS private key migrated from state"
      }
    }
  }' \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars"
```

Replace `<extracted_value>` with the actual private key from state.

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

### Update Module Configuration

If using as a module:

```hcl
module "tls_migrator" {
  source  = "..."
  version = "~> 2.0"  # ← upgraded from v1.x

  # Ephemeral mode is now default
}
```

If using as root module, no version change needed - just ensure you've pulled latest code.

### Initialize Upgrade

```bash
terraform init -upgrade
```

Expected output:
```
Upgrading modules...
- tls_migrator in ...
  Downloading ... 2.0.0 for tls_migrator...
```

## Step 5: Validate Upgrade

### Plan Upgrade

```bash
terraform plan -out=upgrade.tfplan
```

### Expected Output

```
# tls_private_key.legacy has moved to tls_private_key.legacy_resource[0]
  resource "tls_private_key" "legacy_resource" {
      # (no changes)
  }

# vault_kv_secret_v2.legacy has moved to vault_kv_secret_v2.secret[0]
~ resource "vault_kv_secret_v2" "secret" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
  }

Plan: 0 to add, 1 to change, 0 to destroy.
```

**Validation:**
- ✅ Only `moved` operations and write-only attribute updates
- ✅ No resource creates or destroys (in v2.0 ephemeral mode)
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
# version = "~> 1.0"

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

**Fix:** Module should use `one(resource[*].attr)` pattern. Report bug to module maintainer.

### Unexpected resource creates or destroys

**Issue:** Plan shows infrastructure additions or deletions.

**Fix:**
1. Do NOT apply
2. Review [UPGRADE-GUIDE-2.0.md](./UPGRADE-GUIDE-2.0.md) for known issues
3. Verify module version is correct
4. Report issue if persists

## Commands Reference

```bash
# Backup state
terraform state pull > state.backup

# Detect module usage
terraform state list | grep 'tls_private_key\|vault_kv_secret'

# Extract TLS private key
terraform state pull | jq -r '.resources[] | select(.type == "tls_private_key") | .instances[0].attributes.private_key_pem'

# Write workspace variable
curl -s --request POST \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data '{"data":{"type":"vars","attributes":{"key":"<name>","value":"<value>","category":"terraform","sensitive":true}}}' \
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

**Q: How do I rotate ephemeral secrets?**
- Increment `secret_version` variable in v2.0

## Related Documentation

- [UPGRADE-GUIDE-2.0.md](../UPGRADE-GUIDE-2.0.md) - Full upgrade guide
