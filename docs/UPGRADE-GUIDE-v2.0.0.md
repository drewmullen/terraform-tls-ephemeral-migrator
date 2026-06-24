# Upgrade from v1.x to v2.0.0

## What Changed

Secrets are fully removed from Terraform state for all deployments. The legacy
secret-generating resource has been replaced with an ephemeral resource.

## New Deployments

No action required. Secrets are never written to state.

## Existing Deployments — One-Time Migration Required

You must extract your current secret value and pass it as an ephemeral input variable
on your first apply after upgrading. After that apply, delete the workspace variable —
it is never needed again.

### Step 1: Extract secret from state into env var

```bash
SECRET_TLS_KEY=$(terraform state pull | jq -r '
  .resources[]
  | select(.type == "tls_private_key" and .name == "legacy")
  | .instances[0].attributes.private_key_pem
')
```

### Step 2: Write secret to HCP Terraform workspace as sensitive variable

```bash
TFC_TOKEN="<your-api-token>"
WORKSPACE_ID="<your-workspace-id>"
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
        \"value\": $(echo "$SECRET_TLS_KEY" | jq -Rs .),
        \"category\": \"terraform\",
        \"sensitive\": true,
        \"description\": \"One-time migration: legacy TLS private key from state\"
      }
    }
  }" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars"
```

### Step 3: Upgrade module and apply

```bash
terraform init -upgrade
terraform apply
```

On this apply:
- `removed` block removes the legacy resource from state (nothing destroyed)
- `var.tls_private_key_data` feeds the preserved value into the write-only attribute
- Secret is preserved, state is clean

### Step 4: Delete the workspace variable

```bash
VAR_ID=$(curl -s \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars" | \
  jq -r '.data[] | select(.attributes.key == "tls_private_key_data") | .id')

curl -s \
  --request DELETE \
  --header "Authorization: Bearer $TFC_TOKEN" \
  "$TFC_API/workspaces/$WORKSPACE_ID/vars/$VAR_ID"
```

## Rollback

Before apply:
```bash
terraform state pull > tfstate-before-upgrade-$(date +%Y%m%d-%H%M%S).backup
```

After apply, rollback requires re-importing the removed resource.
