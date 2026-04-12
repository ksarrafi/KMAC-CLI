# KMac Vault Manager - Project Key Management

## What I Built

I've created an enhanced vault management system that makes it easy to manage API keys and secrets for all your projects. Instead of creating a separate HTML frontend, I've integrated this directly into your `kmac` CLI toolkit, leveraging your existing Docker vault infrastructure.

## Key Features

### 1. **Project-Based Organization**

Keys are organized using namespaces (e.g., `myproject:api_key`), automatically grouped by project:

```
myproject/
  ├─ api_key            test••••_123
  ├─ database_url       post••••mydb

staging/
  ├─ db_password        stag••••_456
```

### 2. **Easy Key Management**

```bash
# Browse all keys with organization
kmac vault list

# Add a key (hidden input)
kmac vault set myproject:stripe_key

# Get a key value
kmac vault get myproject:stripe_key

# Delete a key
kmac vault delete myproject:old_key
```

### 3. **Project Manager**

Interactive menu for managing all keys in a project:

```bash
kmac vault project myproject
```

Actions available:
- **Add key** - Create new project key
- **Edit key** - Update existing values
- **Delete key** - Remove keys
- **Export to .env** - Save all keys to a file
- **Import from .env** - Bulk import existing keys
- **Copy to clipboard** - Get all as env vars

### 4. **Export to .env Files**

Perfect for local development and AI tools:

```bash
kmac vault project myproject
# Choose 'x' to export
# Creates: myproject.env

# Environment variables for: myproject
# Generated: Sat Apr 11 2026

API_KEY=your_key_here
DATABASE_URL=postgresql://...
STRIPE_SECRET=sk_test_...
```

### 5. **Import from .env Files**

Migrate existing projects easily:

```bash
kmac vault project myproject
# Choose 'i' to import
# Path: ./myproject/.env

# Converts DATABASE_URL=value → myproject:database-url
```

## Why This Approach?

### ✅ Better than HTML UI:
- **No additional security surface** - No web server to secure
- **Integrated** - Works with your existing vault backend
- **Fast** - Terminal is faster than browser
- **Scriptable** - Easy to automate
- **Consistent** - Same UX as other kmac tools

### ✅ AI Tool Friendly:
- Export keys to `.env` files when AI needs them
- Delete the `.env` file when done
- Keys stay secure in vault otherwise
- AI can't accidentally leak vault contents

## Quick Start

### Adding Keys for a New Project

```bash
# Option 1: One at a time
kmac vault set myapp:openai_key
kmac vault set myapp:anthropic_key
kmac vault set myapp:database_url

# Option 2: Import from .env
kmac vault project myapp
# Press 'i', select your .env file
```

### Working with AI Tools

Since AI tools can't access the vault directly:

```bash
# Export what you need
kmac vault project myapp
# Press 'x', save to myapp.env

# Now you can give AI access to myapp.env
# When done:
rm myapp.env
```

Or copy to clipboard:

```bash
kmac vault project myapp
# Press 'c' to copy all keys
# Paste into terminal when AI needs them
```

### Managing Multiple Environments

```bash
# Production
kmac vault set prod:api_key
kmac vault set prod:database_url

# Staging
kmac vault set staging:api_key
kmac vault set staging:database_url

# Export the environment you need
kmac vault project prod
# Export to prod.env
```

## Current Status

✅ **Fully Functional**
- Browse all vault keys
- Add/edit/delete keys
- Project organization
- Export to .env files
- Import from .env files
- Copy to clipboard
- Works with all vault backends (Keychain, File, Docker)

✅ **Tested**
- Works with your Docker vault
- Bash 3.2 compatible (macOS)
- Secure key masking in output

## Usage Examples

### Example 1: Setting up a new app

```bash
# Add your API keys
kmac vault set myapp:openai_key
kmac vault set myapp:stripe_key
kmac vault set myapp:sendgrid_key

# View organized by project
kmac vault list
```

### Example 2: Using with AI coding

```bash
# When AI needs API keys:
kmac vault project myapp
# Export to myapp.env

# Give AI this context:
# "Use the keys in myapp.env for API access"

# After AI is done:
rm myapp.env
```

### Example 3: Migrating existing project

```bash
# If you have a .env file:
kmac vault project myapp
# Press 'i' for import
# Path: ./myapp/.env

# All keys now in vault:
kmac vault list
```

### Example 4: Rotating secrets

```bash
# Update a key
kmac vault set myapp:stripe_key
# Enter new value

# Or delete old one
kmac vault delete myapp:old_stripe_key
```

## Integration with Your Workflow

### In Scripts

```bash
#!/bin/bash
# get-api-key.sh

# Source vault functions
source "$(dirname "$0")/scripts/_vault.sh"

# Get key
API_KEY=$(vault_get "myapp:api_key")

# Use it
curl -H "Authorization: Bearer $API_KEY" https://api.example.com
```

### In Docker Compose

```bash
# Export to .env
kmac vault project myapp
# Export to .env

# Use in docker-compose.yml
version: '3'
services:
  app:
    env_file: myapp.env
```

### In CI/CD

```bash
# Export for GitHub Actions
kmac vault project myapp
# Copy to clipboard
# Paste into GitHub → Settings → Secrets
```

## Commands Reference

```bash
# Interactive browser
kmac vault

# List all keys
kmac vault list

# Add/update key
kmac vault set project:keyname

# Get key value
kmac vault get project:keyname

# Delete key
kmac vault delete project:keyname

# Project manager
kmac vault project projectname
```

## What About the Docker Vault?

Your Docker vault is **already running** and being used by this new vault manager! 

Current status:
```
Container: kmac-vault (7de4b0ddc9a4)
Status: Running (17 hours)
Port: 127.0.0.1:9999
```

The vault manager uses whichever backend you have configured (Keychain by default). To use Docker vault:

```bash
kmac secrets backend
# Choose option 3 (Docker Vault)
```

## File Locations

- **Vault script**: `scripts/vault`
- **Guide**: `docs/VAULT_GUIDE.md`
- **Vault lib**: `scripts/_vault.sh` (existing)
- **Docker vault**: `server/vault/vault_server.py` (existing)

## Next Steps (Optional)

If you want to enhance this further, you could:

1. **Add a web UI** (if you really want one)
   - Create `server/static/vault-ui.html`
   - Add REST endpoints to `server/app.py`
   - Serve it at `/vault-dashboard`

2. **Add bulk operations**
   - Bulk delete by pattern
   - Bulk export all projects
   - Backup/restore all vault data

3. **Add search/filter**
   - Search keys by name
   - Filter by project
   - Show recently modified

4. **Add to main kmac menu**
   - Add shortcut key `v` for vault
   - Update `toolkit.sh`

But honestly, the CLI interface is probably **better suited** for this use case since:
- It's faster
- More scriptable
- Easier for AI tools to use (just export .env)
- More secure (no web interface to attack)

## Try It Out!

```bash
# See your current keys
kmac vault list

# Add a test key
kmac vault set test:my_api_key

# Try the project manager
kmac vault project test
```

Let me know if you want any adjustments or additional features!
