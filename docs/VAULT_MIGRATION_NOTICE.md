# 🔐 Central Vault Migration Notice

## Summary

**All project secrets have been consolidated into KMac Vault** (kmac-vault on port 9999).

**✅ COMPLETE**: All secrets migrated, old vaults removed, keychain purged.

---

## Current State

**Single Central Vault**: kmac-vault (Docker)
- **Port**: 127.0.0.1:9999
- **Token**: ~/.config/kmac/docker-vault-token
- **Status**: ✅ Running
- **Total Keys**: 11 keys across 3 projects

**Removed Vaults**:
- ✅ tron-vault (port 13001) — stopped & removed
- ✅ fc-vault (port 8200) — stopped & removed  
- ✅ macOS Keychain entries — all purged

**Default Backend**: Docker (was Keychain)

---

## What Changed

### ✅ New Central Vault
- **Container**: `kmac-vault`
- **Port**: `127.0.0.1:9999`
- **Token**: `~/.config/kmac/docker-vault-token`
- **API**: REST API (see below)

### ❌ Deprecated Vaults
- **tron-vault** (port 13001) — STOPPED
- **fc-vault** (port 8200) — STOPPED
- All secrets from these vaults have been migrated

---

## For Project Owners

### Tron Project

Your secrets have been migrated to kmac-vault with the `tron:` prefix:

```
tron:auth_jwt_secret    → (migrated from tron/auth/jwt-secret)
tron:auth_master_key    → (migrated from tron/auth/master-key)
tron:auth_secret_key    → (migrated from tron/auth/secret-key)
tron:db_password        → (migrated from tron/db/password)
tron:redis_password     → (migrated from tron/redis/password)
```

**Update `docker-compose.yml`:**

```yaml
environment:
  # Old (tron-vault)
  # VAULT_ADDR: http://vault:8200
  # VAULT_AUTH_METHOD: token
  # VAULT_SECRET_PREFIX: tron

  # New (kmac-vault)
  KMAC_VAULT_URL: http://host.docker.internal:9999
  KMAC_VAULT_TOKEN_FILE: /vault-token
  KMAC_VAULT_PREFIX: "tron:"

volumes:
  # Mount kmac-vault token
  - ~/.config/kmac/docker-vault-token:/vault-token:ro
```

**Update your code** to use kmac-vault REST API (see below).

---

## KMac Vault REST API

### Authentication
```bash
TOKEN=$(cat ~/.config/kmac/docker-vault-token)
```

### Get a Secret
```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:9999/get/tron:db_password
```

**Response:**
```json
{"value": "your-secret-value"}
```

### Set a Secret
```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "project:key_name", "value": "secret-value"}' \
  http://127.0.0.1:9999/set
```

### List All Keys
```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:9999/list
```

### Delete a Secret
```bash
curl -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"key": "project:key_name"}' \
  http://127.0.0.1:9999/delete
```

### Health Check (no auth)
```bash
curl http://127.0.0.1:9999/health
```

---

## Using KMac CLI

The easiest way to manage secrets:

```bash
# Interactive vault manager
kmac vault

# Browse all secrets
kmac vault list

# Add a secret (wizard)
kmac vault set

# Get a secret
kmac vault get tron:db_password

# Project manager (export to .env, etc.)
kmac vault project tron
```

---

## Migration Verification

Check that your secrets were migrated:

```bash
# Using kmac CLI
kmac vault list | grep "tron:"

# Using curl
TOKEN=$(cat ~/.config/kmac/docker-vault-token)
curl -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:9999/list | grep "tron:"
```

---

## Benefits of Central Vault

✅ **Single source of truth** — All projects use one vault  
✅ **Consistent API** — Same REST endpoints for all projects  
✅ **Better security** — Encrypted at rest (Fernet/AES-128-CBC)  
✅ **Easy management** — Use `kmac vault` UI or REST API  
✅ **Project organization** — Keys organized by `project:name` convention  
✅ **Metadata tracking** — Created/updated timestamps for all keys  

---

## Need Help?

- **Documentation**: `docs/VAULT_GUIDE.md`
- **Quick help**: `kmac vault --help`
- **Interactive help**: Press `h` in `kmac vault` menu

---

## Old Vaults (Removed)

The following vaults have been stopped and removed:

```bash
# tron-vault (HashiCorp Vault) - port 13001
docker stop tron-vault && docker rm tron-vault

# fc-vault (HashiCorp Vault) - port 8200  
docker stop fc-vault && docker rm fc-vault
```

If you need to restore the old setup, contact the system administrator.
