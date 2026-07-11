# Vaultwarden

**Host**: Storage node | **Domain**: vault.example.com

## Overview

Self-hosted password manager (Bitwarden-compatible API server). Runs as a Swarm service.

## Configuration

| Setting | Value |
|---------|-------|
| Domain | https://vault.example.com |
| Signups | Disabled |
| Admin token | Docker secret |
| Data dir | `/DATA/Apps/vaultwarden/data/` |

## Deployment

Part of the apps stack, constrained to the storage node.
Traefik routes `vault.example.com` → vaultwarden:80.
