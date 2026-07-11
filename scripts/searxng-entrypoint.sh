#!/bin/sh
# entrypoint wrapper — merges homelab bangs into SearXNG, then runs original entrypoint

set -u

# Run the bang merger if the file exists
if [ -f /etc/searxng/merge-homelab-bangs.py ]; then
    python3 /etc/searxng/merge-homelab-bangs.py
fi

# Exec the original entrypoint
exec /usr/local/searxng/entrypoint.sh
