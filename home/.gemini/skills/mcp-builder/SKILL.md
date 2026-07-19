---
name: mcp-builder
description: Guide for building Model Context Protocol (MCP) servers with JSON-RPC tools, resources, and prompt templates.
---

# MCP Server Builder

Guide for designing, implementing, testing, and registering Model Context Protocol (MCP) servers.

## Server Schema Structure

MCP servers expose three core capabilities:
1. **Tools**: Executable functions with JSON schema arguments.
2. **Resources**: URI-addressable static or dynamic content.
3. **Prompts**: Reusable prompt templates with named parameters.

## Implementation Checklist

1. Define tool schemas with explicit parameter descriptions, types, and required fields.
2. Implement JSON-RPC 2.0 endpoint handler over stdio or SSE.
3. Place tool schemas under `<configDir>/mcp/<server-name>/<tool-name>.json`.
4. Test tool calls locally using `call_mcp_tool`.
