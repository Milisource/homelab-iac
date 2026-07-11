#!/usr/bin/env python3
"""Merge homelab bangs into SearXNG's external_bangs.json at startup.

Reads the Docker-provided external_bangs.json and merges in entries
from /etc/searxng/homelab-bangs.json. Homelab entries are injected
into the trie so they work as !!bang shortcuts.

Runs before SearXNG's web server starts. Mount this script + the
homelab-bangs.json into /etc/searxng/ and configure as the container
entrypoint wrapper.
"""

import json, os, sys

DATA_FILE = "/usr/local/searxng/searx/data/external_bangs.json"
HOMELAB_BANGS = "/etc/searxng/homelab-bangs.json"

LEAF_KEY = chr(16)
SEP = chr(1)
QRY = chr(2)

def main():
    if not os.path.exists(HOMELAB_BANGS):
        print(f"[bangs] No homelab-bangs.json found at {HOMELAB_BANGS}, skipping merge")
        return

    with open(HOMELAB_BANGS) as f:
        homelab = json.load(f)

    with open(DATA_FILE) as f:
        data = json.load(f)

    trie = data.setdefault("trie", {})

    count = 0
    for entry in homelab:
        bang = entry.get("t", "")
        if not bang:
            continue

        url = entry.get("u", "")
        if "{{{s}}}" not in url:
            continue

        rank = str(entry.get("r", 0))

        # Normalize URL: strip https: prefix (stored as //...)
        url = url.replace("{{{s}}}", QRY)
        if url.startswith("https://"):
            url = url[len("https:"):]

        bang_def = url + SEP + rank

        # Walk the trie and set the leaf
        node = trie
        for ch in bang:
            if ch not in node or not isinstance(node[ch], dict):
                node[ch] = {}
            node = node[ch]
        node[LEAF_KEY] = bang_def
        count += 1

    with open(DATA_FILE, "w") as f:
        json.dump(data, f, indent=4, sort_keys=True, ensure_ascii=False)

    print(f"[bangs] Merged {count} homelab bang(s) into external_bangs.json")

if __name__ == "__main__":
    main()
