---
name: summarize
description: "Use when asked to summarize, condense, or get the gist of anything — URLs, documents, PDFs, YouTube videos, audio, code files, git history, PRs, issues, articles, or any large body of text. Also use when the user says 'what is this', 'TLDR', 'explain this link', 'what happened in this PR', or shares a URL and wants to understand it. If the summarize CLI is installed, prefer it for URLs and media."
---

# Summarize

Produce concise, structured summaries of any content.

## Summarize CLI (Preferred for URLs/Media)

If the `summarize` CLI is installed, use it for URLs, YouTube, PDFs, and audio via `run_command`:

```bash
# Install
brew install steipete/tap/summarize

# Summarize a URL
summarize "https://example.com/article"

# Summarize a PDF
summarize "/path/to/file.pdf"

# Summarize a YouTube video
summarize "https://youtu.be/dQw4w9WgXcQ" --youtube auto

# Control output length
summarize "https://example.com" --length short    # short/medium/long/xl/xxl
summarize "https://example.com" --length 500      # character count

# Extract content without summarizing
summarize "https://example.com" --extract-only

# JSON output
summarize "https://example.com" --json
```

**Configuration:** `~/.summarize/config.json` for default model/preferences.

## Built-in Summarization (Antigravity Tools)

For content accessible via native tools, summarize directly:

| Input | How to Access |
|-------|---------------|
| URL/webpage | `read_url_content(Url=...)` or `search_web(query=...)` |
| PDF / Image file | `view_file(AbsolutePath=...)` |
| Code file | `view_file(AbsolutePath=...)` |
| Git history | `run_command(CommandLine="git log -n 10 --oneline", Cwd=...)` |
| GitHub issue/PR | `run_command(CommandLine="gh issue view N", Cwd=...)` or `gh pr view N` |
| Directory | `list_dir` / `find_by_name` + selective `view_file` of key files |

## Output Format

Use this structure unless the user specifies otherwise:

```markdown
## Summary

[2-3 sentence overview]

## Key Points

- [Most important takeaway]
- [Second most important]
- [Third most important]

## Details

[Optional: deeper context if warranted]
```

## Guidelines

- Lead with the most important information
- Use bullet points over paragraphs
- Include specific numbers, names, and dates when relevant
- For code: focus on what it does, not how (unless asked)
- For PRs/issues: include status, key decisions, blockers
- Default to ~200 words unless asked for more/less detail
- Preserve technical accuracy — don't simplify to the point of being wrong
