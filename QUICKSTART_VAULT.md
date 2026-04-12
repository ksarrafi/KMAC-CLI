# Quick Start: Vault Manager

## What I Built for You

✅ **Project-based key management** for your KMac vault
✅ **CLI interface** - no HTML UI needed (faster & more secure)
✅ **AI-friendly** - export keys to `.env` when AI needs them
✅ **Works with your existing Docker vault** (running on port 9999)

## Try It Now

### 1. Browse your current keys

```bash
kmac vault list
```

You'll see keys organized by project:

```
myproject/
  ├─ api_key            test••••_123
  ├─ database_url       post••••mydb

staging/
  ├─ db_password        stag••••_456
```

### 2. Add keys for a project

```bash
# Use format: project:keyname
kmac vault set myapp:openai_key
kmac vault set myapp:stripe_key
kmac vault set myapp:database_url
```

### 3. Manage a project

```bash
kmac vault project myapp
```

This opens an interactive menu where you can:
- **Add** new keys
- **Edit** existing keys
- **Delete** keys
- **Export** to `.env` file (for local dev or AI)
- **Import** from `.env` file
- **Copy** all keys to clipboard

### 4. Export for AI tools

When AI needs your keys:

```bash
kmac vault project myapp
# Press 'x' to export
# File: myapp.env

# Now give AI access to myapp.env
# When done: rm myapp.env
```

## Common Commands

```bash
# Browse all keys (organized by project)
kmac vault list

# Add/update a key
kmac vault set project:keyname

# Get a key value (for scripts)
kmac vault get project:keyname

# Delete a key
kmac vault delete project:keyname

# Interactive project manager
kmac vault project projectname
```

## Real Example

Let's set up a project:

```bash
# Add your keys
kmac vault set myapp:openai_key
kmac vault set myapp:anthropic_key
kmac vault set myapp:database_url
kmac vault set myapp:stripe_secret

# View them organized
kmac vault list

# Export to .env for development
kmac vault project myapp
# Press 'x', creates myapp.env

# Use in your app
source myapp.env
npm run dev

# When AI needs keys:
# Give AI: "Use the keys in myapp.env"
# After: rm myapp.env
```

## Already Working!

Your Docker vault is **already running**:
- Container: `kmac-vault` (7de4b0ddc9a4)
- Port: `127.0.0.1:9999`
- Status: Running (17+ hours)

The vault manager uses your configured backend (currently: **keychain**).

## Documentation

- **Full Guide**: `docs/VAULT_GUIDE.md`
- **Overview**: `VAULT_MANAGER.md`
- **Vault Script**: `scripts/vault`

## Why This is Better Than HTML UI

1. **Faster** - Terminal is instant
2. **More secure** - No web server to attack
3. **Scriptable** - Easy to automate
4. **AI-friendly** - Just export .env when needed
5. **Integrated** - Works with existing kmac tools

## Need Help?

```bash
# View all commands
kmac vault

# Or press 'h' in any menu for help
```

Enjoy! 🚀
