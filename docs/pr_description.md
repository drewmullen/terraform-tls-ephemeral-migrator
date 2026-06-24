## Description

Fully removes secrets from Terraform state. All deployments — new and existing — will
have clean state after this upgrade.

## Version

**MAJOR VERSION BUMP** (v1.1.1 → v2.0.0)

⚠️ **BREAKING CHANGE**: Existing users must perform a one-time migration step.

## Impact

### New Deployments
No changes required. Secrets are ephemeral and never written to state.

### Existing Deployments
One-time manual step required on first apply:
1. Extract secret from state into env var
2. Write to HCP Terraform workspace as sensitive variable
3. Apply upgrade — secret preserved, removed from state
4. Delete the temporary workspace variable

Full instructions: `docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md`

## Changes

### `variables.tf`
- `tls_private_key_data` (string, ephemeral, sensitive, default: null) — one-time migration input
- `secret_version` (number, default: 1) — increment to re-write write-only secret

### Resource Changes
- `removed { lifecycle { destroy = false } }` replaces legacy `tls_private_key.legacy`
- `ephemeral "tls_private_key" "legacy"` added
- `vault_kv_secret_v2.legacy` updated to `data_json_wo` write-only attribute with conditional

## Documentation
- `docs/UPGRADE-GUIDE-v2.0.0.md` — full upgrade guide
- `docs/skills/tf-ephemeral-upgrade-terraform-tls-ephemeral-migrator.md` — step-by-step upgrade assistant
