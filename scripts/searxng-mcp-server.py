#!/usr/bin/env python3
"""SearXNG MCP server using the official MCP SDK."""

import os, json, urllib.request, urllib.parse
from mcp.server.fastmcp import FastMCP

SEARXNG_BASE_URL = os.environ.get("SEARXNG_BASE_URL", "https://search.example.com")
mcp = FastMCP("searxng-mcp", instructions="Search the web using SearXNG metasearch engine")


def search_searxng(query: str, category: str = "general", language: str = "en-US", max_results: int = 10) -> str:
    params = urllib.parse.urlencode({
        "q": query, "format": "json", "language": language,
        "categories": category, "pageno": 1,
    })
    url = f"{SEARXNG_BASE_URL}/search?{params}"
    try:
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
        results = data.get("results", [])
        answers = data.get("answers", [])
        infoboxes = data.get("infoboxes", [])
        lines = []
        if answers:
            lines.append("## Direct Answers")
            for a in answers[:3]:
                lines.append(f"- {a}")
        if infoboxes:
            lines.append("\n## Infobox")
            for ib in infoboxes[:1]:
                lines.append(f"**{ib.get('infobox', '')}**")
                if ib.get("content"):
                    lines.append(ib["content"])
        lines.append(f"\n## Search Results ({len(results)} found)")
        for i, r in enumerate(results[:max_results], 1):
            title = r.get("title", "No title")
            url_result = r.get("url", "")
            content = r.get("content", "")
            engine = r.get("engine", "?")
            snippet = content[:300] if content else ""
            lines.append(f"\n{i}. **{title}**")
            lines.append(f"   URL: {url_result}")
            if snippet:
                lines.append(f"   {snippet}")
            lines.append(f"   (via {engine})")
        return "\n".join(lines)
    except urllib.error.HTTPError as e:
        return f"Search error (HTTP {e.code}): {e.read().decode()[:500]}"
    except Exception as e:
        return f"Search error: {e}"


@mcp.tool(description="Search the web using the self-hosted SearXNG metasearch engine")
def searxng_web_search(query: str, language: str = "en-US", categories: str = "general", max_results: int = 10) -> str:
    return search_searxng(query, categories, language, max_results)


@mcp.tool(description="Search for images using SearXNG")
def searxng_search_images(query: str, max_results: int = 10) -> str:
    return search_searxng(query, "images", "en-US", max_results)


@mcp.tool(description="Search for news using SearXNG")
def searxng_search_news(query: str, max_results: int = 10) -> str:
    return search_searxng(query, "news", "en-US", max_results)


if __name__ == "__main__":
    mcp.run(transport="stdio")
