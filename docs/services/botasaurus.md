# Botasaurus — Web Scraping Framework (Consideration)

**Status**: Not deployed | **Source**: [omkarcloud/botasaurus](https://github.com/omkarcloud/botasaurus) | **License**: MIT
**Stars**: ~4.7k | **PyPI**: `botasaurus` (v4.0.97, Jan 2026) | **Python**: >=3.7

## Summary

Botasaurus is a meta-package wrapping Selenium-based browser automation with anti-detection patches. It bypasses Cloudflare WAF, Turnstile, Datadome, Fingerprint, and BrowserScan by sanitizing WebDriver properties, spoofing navigator APIs, injecting realistic mouse movement, and using Google-referrer strategies. Provides three decorator-based APIs (`@browser`, `@request`, `@task`) with built-in caching, parallelization, proxy rotation, and profile management.

## Key Features

- **Anti-detection**: Passes Cloudflare (JS+CAPTCHA), Turnstile, Datadome, BrowserScan, Fingerprint
- **`@browser` decorator**: Humane Selenium driver with stealth patches, `google_get()` for referrer-based bypass
- **`@request` decorator**: Lightweight HTTP mode with browser-like headers (no Chrome needed)
- **`@task` decorator**: Generic parallelization/caching for any Python function
- **Proxy support**: Static, rotating, and function-derived (per-data-item) proxies
- **Caching**: Built-in output to JSON, retry logic, error recovery (opens browser for debugging even in headless mode)
- **Profile management**: Tiny profiles (~1KB) for cookie/session persistence at scale
- **REST API mode**: `botasaurus-server` exposes scrapers as web services with auto-generated API docs
- **Desktop app generator**: Cross-platform (Mac/Win/Linux) Electron-like desktop extractors
- **CAPTCHA solving**: Plugin for Capsolver extension
- **Chrome extensions**: Load any CRX extension with 1 line of code
- **Kubernetes support**: Scale to multiple machines

## Architecture

```
botasaurus (meta-package)   ← pip install botasaurus
├── botasaurus-driver       ← Selenium wrapper + stealth patches
├── botasaurus-requests     ← Browser-like HTTP client
├── botasaurus-api          ← REST API / UI server
├── botasaurus-humancursor  ← Realistic mouse movement
├── botasaurus-proxy-auth   ← Proxy auth handling
├── bota                    ← Utilities (JSON/Excel/HTML output, data cleaning)
└── close_chrome            ← Chrome instance cleanup
```

## Why It Matters for the Homelab

- AI agents hitting Cloudflare-protected sites will fail with raw `requests` — Botasaurus gives them a path through
- Can be deployed as a containerized REST scraping microservice that other agents call
- The `@request` decorator alone is a drop-in replacement for `httpx`/`requests` with better evasion defaults
- Caching at the framework level avoids redundant agent fetches
- Parallelization built in — useful for batch data collection tasks

## Concerns

- Anti-detection is a cat-and-mouse game — may break after Chrome updates
- The README is heavily marketing (ignore the tone, test the substance)
- 54 open issues on GitHub
- In browser mode, inherits Selenium's overhead (Chrome process per task)
- Botasaurus-driver internals are opaque — sub-packages under omkarcloud's namespace, not independently audited
- Real-world efficacy varies by target site's WAF config

## Potential Deployment

Not yet deployed. If adopted, likely as a containerized REST service on the Docker swarm, callable by Hermes and n8n. The `@request` decorator could also be used directly within agent Python scripts without a standalone service.

## Comparison: Botasaurus vs. Camofox

Both solve the same core problem (accessing protected web content) but at different layers and for different usage patterns.

| Dimension | Botasaurus | Camofox |
|-----------|-----------|---------|
| **Stealth approach** | JS-level patches (WebDriver, navigator APIs via Selenium) | C++-level patches (navigator, WebGL, AudioContext, WebRTC — before JS runs) |
| **Browser engine** | Chrome/Chromium | Firefox (Camoufox fork) |
| **API style** | Python decorators (`@browser`, `@request`, `@task`) | REST API (`POST /tabs`, snapshot, click, type) |
| **Deployment** | Library imported in Python, or optional REST server | Standalone REST server (port 9377) |
| **Best for** | Batch data extraction (1000 URLs, caching, parallel, retry) | Agent-driven interactive browsing (go here, click that, tell me) |
| **HTTP-only mode** | Yes (`@request` decorator — no browser needed) | No (always spins up Firefox) |
| **Caching** | Built-in (JSON output, retry, dedup) | None (stateless between sessions) |
| **Parallelization** | Decorator-based (`@browser(parallel=N)`) | Manual (multi-tab via API) |
| **Proxy rotation** | Built-in (list or function-derived per task) | External (env var or container-level) |
| **CAPTCHA solving** | Plugin (Capsolver extension) | None |
| **Desktop app gen** | Yes (Electron-like cross-platform) | No |
| **UI server** | Yes (`botasaurus-server`, auto API docs) | No |
| **Currently deployed** | No | Yes (heavensfeel, used by Hermes) |

### When to use which

**Camofox** is the right choice when an AI agent needs to *interact* with a page — logging in, filling forms, clicking through pagination, reading rendered state. Its REST API maps naturally to agent tool calls, and the C++-level stealth is harder to detect. Already integrated with Hermes.

**Botasaurus** is the better choice when you need to *extract data at scale* — 500 product pages, 10K search results, recurring batch jobs. The `@request` mode costs zero browser overhead, the caching/retry/parallelization is built-in, and `@browser` can fall back to full Chrome when `@request` hits a wall (e.g., JS-rendered content).

They are **complementary**, not replacements. If both were deployed:
- Camofox handles interactive agent browsing (Hermes's "go check this page" use case)
- Botasaurus handles scheduled/scripted batch extraction (n8n workflows, cron scraping jobs)
- Both route through proxies, both bypass Cloudflare — at different layers and with different trade-offs

## See Also

- camofox — Existing stealth browser REST API
- other-services — Also fetches web pages, may benefit from Botasaurus's evasion
- hermes — Agent that frequently needs to access protected web content
