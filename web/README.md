# PDAC Database Query Tool

A React-based web UI for querying and exploring the PDAC Azure SQL Server database.

## Features

- **Query Execution** — Execute SQL queries with timeout protection
- **Schema Browser** — Browse tables, columns, and row counts
- **Results Display** — Virtualized table view for large datasets
- **CSV Export** — Export results as CSV
- **Connection Status** — Real-time database connection monitoring

## Development

### Setup

```bash
cd web
npm install
```

### Dev Server

```bash
npm run dev
```

Server runs on http://localhost:5173 with proxy to http://localhost:7890

### Build

```bash
npm run build
```

Output goes to `dist/` for serving as static files.

### Testing

```bash
npm run test
npm run test:coverage
```

## Architecture

- **Frontend**: React 18 + TypeScript + Tailwind CSS + Vite
- **Backend**: Python/aiohttp endpoints at `/api/pdac/*`
- **Database**: Azure SQL Server via pyodbc
- **Auth**: Vault-based credentials (no credentials in code)

## Environment

PDAC connection credentials are loaded from vault at runtime:
- `pdac_reporting:connectionstring` — Full Azure SQL connection string
- Or fallback to: `pdac_reporting:server`, `pdac_reporting:user`, `pdac_reporting:password`

Vault token automatically loaded from `~/.config/kmac/docker-vault-token`
