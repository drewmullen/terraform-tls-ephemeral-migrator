# Upgrade from v1.x to v2.0.0

## What Changed

The legacy state migration path has been removed. All deployments exclusively use ephemeral
resources for the TLS private key. The `tls_private_key_data` migration variable introduced
in v1.2 has been removed. State is always clean.

## New Deployments

No action required. Upgrade the module version and apply:

```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"
}
```

```bash
terraform init -upgrade
terraform apply
```

## Existing Deployments

### Recommended: Stage through v1.2 first

Users on v1.x should upgrade to v1.2 and complete the one-time migration before upgrading to v2.0.
This preserves the existing TLS private key value.

1. **Upgrade to v1.2** — follow `docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md`
2. **Verify state is clean** — no `tls_private_key` resource in state
3. **Upgrade to v2.0** — update version and apply:

```bash
terraform init -upgrade
terraform apply  # no changes expected if v1.2 migration was completed
```

### Direct upgrade from v1.x to v2.0

⚠️ **This regenerates the TLS private key.** Update any downstream systems consuming the certificate/key.

If you accept key regeneration, you can upgrade directly:

```hcl
module "example" {
  source  = "..."
  version = "~> 2.0"
}
```

Expected plan output:
```
# module.example.tls_private_key.legacy[0] has been removed
  (lifecycle.destroy = false — no infrastructure destroyed)

# module.example.vault_kv_secret_v2.legacy will be updated in-place
~ resource "vault_kv_secret_v2" "legacy" {
    ~ data_json    = (sensitive value) -> null
    + data_json_wo = (known after apply)
  }
```

The `removed` block in `main.tf` handles users who still have `tls_private_key.legacy[0]` in state — it removes the resource from state without destroying infrastructure.

## Breaking Changes

- **`tls_private_key_data` variable removed** — if you set this in v1.2, remove it before upgrading
- **`use_ephemeral_key` variable removed** (was removed in v1.2)
- **New key generated on first apply** (for direct v1.x → v2.0 upgraders without staging through v1.2)

## Rollback

Before apply:
```bash
terraform state push tfstate-before-upgrade-<timestamp>.backup
```

After apply, rollback requires re-importing the removed resource and restoring the prior module version.

## Related Documentation

- [docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md](skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md) — Upgrade assistant for v1.x → v1.2 migration
