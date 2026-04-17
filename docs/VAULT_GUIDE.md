# KMac Vault Manager Guide

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Key Naming Convention](#key-naming-convention)
- [Features](#features)
  - [Browse All Keys](#1-browse-all-keys)
  - [Add/Update Keys](#2-addupdate-keys)
  - [Get Key Values](#3-get-key-values)
  - [Project Key Manager](#4-project-key-manager)
  - [Export to .env File](#5-export-to-env-file)
  - [Import from .env File](#6-import-from-env-file)
- [Common Workflows](#common-workflows)
  - [Setting Up a New Project](#setting-up-a-new-project)
  - [Working with Multiple Environments](#working-with-multiple-environments)
  - [Sharing Keys with AI Tools (Safely)](#sharing-keys-with-ai-tools-safely)
  - [Rotating Secrets](#rotating-secrets)
  - [Deleting Keys](#deleting-keys)
- [Integration with KMac Tools](#integration-with-kmac-tools)
- [Backend Selection](#backend-selection)
- [Security Best Practices](#security-best-practices)
- [Troubleshooting](#troubleshooting)
- [Examples](#examples)
- [Advanced Usage](#advanced-usage)
- [Need Help?](#need-help)

---

## Overview

The KMac Vault Manager provides a simple, secure way to manage API keys, tokens, and secrets for all your projects. Keys are stored in your vault backend (Keychain, encrypted file, or Docker) and organized by project namespaces.

## Quick Start

```bash
# Launch interactive vault browser
kmac vault

# Or use CLI commands
kmac vault list                    # Browse all keys
kmac vault set myproject:api_key   # Add a key
kmac vault get myproject:api_key   # Get a key value
kmac vault project myproject       # Project-specific manager
```

## Key Naming Convention

Use project namespacing to organize your keys:

```
project:key_name
```

**Examples:**
- `myapp:api_key`
- `staging:database_url`
- `prod:stripe_secret`
- `client-portal:jwt_secret`

The vault automatically groups keys by project namespace for easy browsing.

## Features

### 1. Browse All Keys

```bash
kmac vault list
```

Shows all keys organized by project:

```
myproject/
  ├─ api_key            test••••_123
  ├─ database_url       post••••5432

Other Keys
  ├─ anthropic          sk-a••••MAAA
  ├─ openai             sk-p••••RssA
```

### 2. Add/Update Keys

```bash
kmac vault set myproject:api_key
# Interactive prompt for value (hidden input)

# Or from command line (useful for scripts)
echo "secret_value" | kmac vault set myproject:api_key
```

### 3. Get Key Values

```bash
# Print to stdout (useful for scripts)
kmac vault get myproject:api_key

# Use in commands
curl -H "Authorization: Bearer $(kmac vault get myproject:api_key)" https://api.example.com
```

### 4. Project Key Manager

```bash
kmac vault project myproject
```

Interactive menu for managing all keys in a project:
- **Add key** - Create new project key
- **Edit key** - Update existing key
- **Delete key** - Remove a key
- **Export to .env** - Save all project keys to an .env file
- **Import from .env** - Bulk import keys from an existing .env file
- **Copy to clipboard** - Get all keys as env vars

### 5. Export to .env File

Perfect for local development:

```bash
kmac vault project myproject
# Choose 'x' to export
# Creates myproject.env with:

# Environment variables for: myproject
# Generated: Sat Apr 11 2026

API_KEY=test_api_key_123
DATABASE_URL=postgresql://...
```

The file is automatically set to `chmod 600` for security.

### 6. Import from .env File

Quickly migrate existing .env files to the vault:

```bash
kmac vault project myproject
# Choose 'i' to import
# Path to .env file: ./myproject/.env
```

Converts `DATABASE_URL=value` → `myproject:database-url`

## Common Workflows

### Setting Up a New Project

```bash
# Option 1: Add keys one by one
kmac vault set myapp:api_key
kmac vault set myapp:db_password
kmac vault set myapp:jwt_secret

# Option 2: Import from existing .env
kmac vault project myapp
# Choose 'i' for import, point to your .env file
```

### Working with Multiple Environments

```bash
# Production keys
kmac vault set prod:api_key
kmac vault set prod:database_url

# Staging keys
kmac vault set staging:api_key
kmac vault set staging:database_url

# Development keys
kmac vault set dev:api_key
kmac vault set dev:database_url
```

Then export the environment you need:

```bash
kmac vault project prod
# Choose 'x' to export → prod.env
```

### Sharing Keys with AI Tools (Safely)

Since AI tools can't access your vault directly, export what you need:

```bash
# Export to .env file
kmac vault project myproject
# Choose 'x', save to myproject.env

# Now you can give the AI tool access to myproject.env
# when needed, and delete it when done
```

Or copy to clipboard:

```bash
kmac vault project myproject
# Choose 'c' to copy all keys to clipboard
# Paste into terminal: export KEY=value
```

### Rotating Secrets

```bash
# Update an existing key
kmac vault set myproject:api_key
# New value overwrites the old one
```

### Deleting Keys

```bash
# Via CLI
kmac vault delete myproject:old_key

# Or via project manager
kmac vault project myproject
# Choose 'd' to delete, select key from list
```

## Integration with KMac Tools

### In Scripts

```bash
#!/bin/bash
source "$(dirname "$0")/_vault.sh"

# Get a key
API_KEY=$(vault_get "myproject:api_key")

# Use it
curl -H "Authorization: Bearer $API_KEY" https://api.example.com
```

### In Your Projects

```bash
# Load project env vars into shell
source <(kmac vault get myproject:api_key | xargs -I{} echo "export API_KEY={}")

# Or export to file and source it
kmac vault project myproject  # export to myproject.env
source myproject.env
```

## Backend Selection

The vault uses your configured backend (Keychain by default):

```bash
# Check current backend
kmac secrets backend

# Switch to Docker vault (recommended for cross-platform)
kmac secrets backend
# Choose option 3 (Docker Vault)
```

**Why use Docker vault?**
- OS-independent (works on macOS and Linux)
- Data stored in encrypted Docker volume
- Easy backup/restore with volume exports
- Isolated from host system

## Security Best Practices

1. **Never commit .env files** - Add `*.env` to `.gitignore`
2. **Use restrictive permissions** - Exported files are automatically `chmod 600`
3. **Delete temporary exports** - Remove .env files after use
4. **Rotate secrets regularly** - Update keys periodically
5. **Use project namespaces** - Keep production and dev keys separate

## Troubleshooting

### Docker vault not starting

```bash
# Check if Docker is running
docker ps

# Start vault manually
kmac secrets docker-start

# Check status
kmac secrets docker-status
```

### Keys not showing up

```bash
# Check backend
kmac secrets backend

# Ensure vault is initialized
kmac secrets list
```

### Import/export issues

```bash
# Check file permissions
ls -la myproject.env

# Verify format (should be KEY=value)
cat myproject.env
```

## Examples

### API Key Management

```bash
# Store API keys for different services
kmac vault set myapp:stripe_secret
kmac vault set myapp:twilio_sid
kmac vault set myapp:sendgrid_key

# Export for local development
kmac vault project myapp
# Choose 'x', creates myapp.env

# In your app:
source myapp.env
npm run dev
```

### Database Credentials

```bash
# Store database URLs
kmac vault set prod:postgres_url
kmac vault set staging:postgres_url

# Use in migrations
export DATABASE_URL=$(kmac vault get prod:postgres_url)
npm run migrate
```

### CI/CD Secrets

```bash
# Export for CI environment
kmac vault project myapp
# Choose 'c' to copy to clipboard
# Paste into GitHub Secrets, GitLab CI variables, etc.
```

## Advanced Usage

### Bulk Set from Script

```bash
#!/bin/bash
# bulk-import.sh

PROJECT="myapp"

cat << EOF | while IFS='=' read -r key value; do
api_key=sk_test_123456
database_url=postgresql://localhost/mydb
jwt_secret=super_secret_key
EOF
  kmac vault set "${PROJECT}:${key}" <<< "$value"
done
```

### Dynamic Environment Selection

```bash
#!/bin/bash
ENV=${1:-dev}  # Default to dev

# Export environment-specific keys
kmac vault project "$ENV"
# Export to ${ENV}.env
```

### Backup All Projects

```bash
#!/bin/bash
# backup-vault.sh

# Get unique project namespaces
PROJECTS=$(kmac vault list | grep '/$' | sed 's|/||')

for proj in $PROJECTS; do
  echo "Backing up $proj..."
  kmac vault project "$proj"
  # Export each to ${proj}.env
done

# Create backup archive
tar czf vault-backup-$(date +%Y%m%d).tar.gz *.env
rm *.env
```

## Coming Soon

- [ ] Web UI for vault management
- [ ] Vault sync across machines
- [ ] Team secret sharing (encrypted)
- [ ] Secret rotation reminders
- [ ] Audit log for key access

## Need Help?

```bash
# View all vault commands
kmac vault --help

# Interactive help
kmac vault
# Press 'h' for help

# Check vault status
kmac secrets list
```
