---
name: tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator
description: >
  Assist with upgrading terraform-tls-ephemeral-migrator from v1.x to v1.2.
  Extracts legacy TLS private key from state into an env var, writes it as a sensitive
  HCP Terraform workspace variable, upgrades module version, and validates.
  After apply, removes the temporary workspace variable.
  Use when upgrading existing deployments to remove the TLS private key from state.
---

# terraform-tls-ephemeral-migrator Upgrade Assistant

Upgrade terraform-tls-ephemeral-migrator from v1.x → v1.2. The TLS private key is fully
removed from state for all deployments. Existing users must perform a one-time step to
preserve their current key value.

## Workflow

1. Detect module usage
2. Backup state
3. Extract TLS private key from state into an env var
4. Write key as a sensitive HCP Terraform workspace variable
5. Upgrade module version and apply
6. Delete the temporary workspace variable

## Prerequisites

- Terraform v1.11+
- `curl` and `jq`
- HCP Terraform API token
- Workspace ID

## Step 1: Detect Module Usage

```bash
grep -rn 'module "terraform-tls-ephemeral-migrator"' . --include="*.tf"
terraform state list | grep 'module\.terraform-tls-ephemeral-migrator'
```

Record workspace ID from HCP Terraform UI (Settings → General) or:

```bash
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/<org>/workspaces/<workspace-name>" \
  | jq -r '.data.id'
```

## Step 2: Backup State

```bash
terraform state pull > tfstate-before-upgrade-$(date +%Y%m%d-%H%M%S).backup
```

## Step 3: Extract TLS Private Key into Env Var

The private key is stored under `tls_private_key.legacy` (v1.0.x) or `tls_private_key.legacy[0]` (v1.1.x).

```bash
SECRET_TLS_PRIVATE_KEY=$(terraform state pull | jq -r '
  .resources[]
  | select(.module == "module.terraform-tls-ephemeral-migrator" and .type == "tls_private_key")
  | .instances[0].attributes.private_key_pem
')
```

Verify the variable is populated (do not print value to stdout):

```bash
[ -n "$SECRET_TLS_PRIVATE_KEY" ] && echo "Key extracted successfully" || echo "ERROR: key not found in state"
```

If empty, the module may already be in ephemeral mode (`use_ephemeral_key = true`). In that case no
extraction is needed — skip to Step 5 and omit `tls_private_key_data`.

## Step 4: Write TLS Key to HCP Terraform Workspace

```bash
TFC_TOKEN="<your-api-token>"
WORKSPACE_ID="<your-workspace-id>"
TFC_API="https://app.terraform.io/api/v2"
```

```bash
curl -s \
  --request POST \
  --header "Authorization: Bearer $TFC_TOKEN" \
  --header "Content-Type: application/vnd.api+json" \
  --data "{
    \"data\": {
      \"type\": \"vars\",
      \"attributes\": {
        \"key\": \"tls_private_key_data\",
        \"value\": $(echo "$SECRET_TLS_PRIVATE_KEY" | jq -Rs .),
        \"category\": \"terraform\",
        \"sensitive\": true,
        \"description\": \"One-time migration: legacy TLS private key from state\"
      }
    }
  }" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars"
```

Verify (sensitive value not shown):

```bash
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | \
  jq '.data[] | {name: .attributes.key, sensitive: .attributes.sensitive}'
```

## Step 5: Upgrade Module and Apply

Update module version:

```hcl
module "terraform-tls-ephemeral-migrator" {
  source  = "..."
  version = "~> 1.2"

  # All other config unchanged — do NOT set tls_private_key_data here,
  # it is read from the workspace variable automatically
}
```

```bash
terraform init -upgrade
terraform plan -out=upgrade.tfplan
```

Expected plan output:

```
# module.terraform-tls-ephemeral-migrator.tls_private_key.legacy[0] has been removed
  (lifecycle.destroy = false — no infrastructure destroyed)

# module.terraform-tls-ephemeral-migrator.vault_kv_secret_v2.legacy will be updated in-place
~ resource "vault_kv_secret_v2" "legacy" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
  }
```

**Validation:**
- ✅ `removed` block — resource leaves state, nothing destroyed
- ✅ Consumer updated to write-only attribute
- ✅ No resource creates or destroys

```bash
terraform apply upgrade.tfplan
```

## Step 6: Delete Temporary Workspace Variable

After a successful apply, the migration variable is no longer needed:

```bash
VAR_ID=$(curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | \
  jq -r '.data[] | select(.attributes.key == "tls_private_key_data") | .id')

curl -s \
  --request DELETE \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars/$VAR_ID"

echo "Migration variable deleted"
```

## Rollback

Before apply:

```bash
terraform state push tfstate-before-upgrade-<timestamp>.backup
```

After apply, rollback requires re-importing the removed resource — contact the module maintainer.

## Troubleshooting

### "Variable is not ephemeral"

**Error:**
```
Error: Invalid use of ephemeral value
```

**Fix:** Verify module version is v1.2+. The `tls_private_key_data` variable must have `ephemeral = true`.

### Plan shows unexpected destroys

**Fix:** Do NOT apply. Verify the workspace variable was created successfully (Step 4). Verify the module version is correct.

### Key not found in state (Step 3)

If the key extraction returns empty, the module was already running in ephemeral mode (`use_ephemeral_key = true`). The key was already being generated ephemerally and is not in state. Skip Step 4 and proceed directly to Step 5 without setting `tls_private_key_data`. A new ephemeral key will be generated on the next apply.

### Workspace variable not found in Step 6

```bash
curl -s --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | jq '.data[].attributes.key'
```

## Related Documentation

- [UPGRADE-GUIDE-v2.0.0.md](../UPGRADE-GUIDE-v2.0.0.md) - Full upgrade guide for v1.x → v2.0
- [README.md](../../README.md)
