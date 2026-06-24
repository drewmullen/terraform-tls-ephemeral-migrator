# terraform-tls-ephemeral-migrator Upgrade Assistant

Upgrade terraform-tls-ephemeral-migrator from v1.x → v2.0.0. Secrets fully removed from state.
Existing users: one-time manual step required to preserve secret values.

## Workflow

1. Detect workspace ID
2. Backup state
3. Extract secret values from state into env vars
4. Write secrets to HCP Terraform workspace as sensitive variables
5. Upgrade and apply
6. Delete temporary workspace variables

## Prerequisites

- Terraform v1.11+
- `curl` and `jq`
- HCP Terraform API token
- Workspace ID

## Step 1: Get Workspace ID

```bash
TFC_TOKEN="<your-api-token>"
ORG="<your-org>"
WORKSPACE="<your-workspace-name>"

WORKSPACE_ID=$(curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "https://app.terraform.io/api/v2/organizations/$ORG/workspaces/$WORKSPACE" \
  | jq -r '.data.id')

echo "Workspace ID: $WORKSPACE_ID"
```

## Step 2: Backup State

```bash
terraform state pull > tfstate-before-upgrade-$(date +%Y%m%d-%H%M%S).backup
```

## Step 3: Extract Secret Values into Env Vars

```bash
SECRET_TLS_PRIVATE_KEY=$(terraform state pull | jq -r '
  .resources[]
  | select(.type == "tls_private_key" and .name == "legacy")
  | .instances[0].attributes.private_key_pem
')

if [ -z "$SECRET_TLS_PRIVATE_KEY" ]; then
  echo "ERROR: tls_private_key.legacy not found in state"
  exit 1
fi

echo "✅ Secret extracted (length: ${#SECRET_TLS_PRIVATE_KEY} chars)"
```

## Step 4: Write Secrets to HCP Terraform Workspace

```bash
TFC_API="https://app.terraform.io/api/v2"

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

echo "✅ Variable created: tls_private_key_data"
```

Verify (sensitive value not shown):
```bash
curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | \
  jq '.data[] | {name: .attributes.key, sensitive: .attributes.sensitive}'
```

## Step 5: Upgrade and Apply

```bash
terraform init -upgrade
terraform plan -out=upgrade.tfplan
```

Expected plan:
```
# tls_private_key.legacy has been removed
  (lifecycle.destroy = false — no infrastructure destroyed)

# vault_kv_secret_v2.legacy will be updated in-place
~ resource "vault_kv_secret_v2" "legacy" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
  }
```

Validation:
- ✅ `removed` — resource leaves state, nothing destroyed
- ✅ Consumer updated to write-only attribute
- ✅ No resource creates or destroys

```bash
terraform apply upgrade.tfplan
```

## Step 6: Delete Temporary Workspace Variables

```bash
VAR_ID=$(curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | \
  jq -r '.data[] | select(.attributes.key == "tls_private_key_data") | .id')

curl -s \
  --request DELETE \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars/$VAR_ID"

echo "✅ Deleted: tls_private_key_data"
```

## Rollback

Before apply:
```bash
terraform state push tfstate-before-upgrade-<timestamp>.backup
```

After apply, rollback requires re-importing removed resource — contact module maintainer.

## Troubleshooting

### "Variable is not ephemeral"
**Fix:** Module version must be v2.0.0+. The `tls_private_key_data` variable requires `ephemeral = true`.

### Plan shows unexpected destroys
**Fix:** Do NOT apply. Verify workspace variables created (Step 4) and module version is correct.

### Workspace variable not found in Step 6
```bash
curl -s --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | jq '.data[].attributes.key'
```

## Related

- [UPGRADE-GUIDE-v2.0.0.md](../UPGRADE-GUIDE-v2.0.0.md)
