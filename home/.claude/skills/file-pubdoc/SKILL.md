---
name: file-pubdoc
description: Draft README.md or visitor-facing markdown (top-level *.md, docs/**/*.md) using the canonical skeleton, complementing the public-doc-durability audit.
---

# File Public Document

Draft visitor-facing markdown (README and `docs/`) using a fixed skeleton so the resulting page documents present-tense, audience-public capability — not the author's session log, rationale dump, or roadmap.

## Audience

The reader is a **stranger who landed on the repo via search or a link**. They do not share the author's session, dotfiles, design history, or reading list. Everything that only makes sense given context the reader does not have is misplaced.

Two questions the page must answer in order:

1. Is this the thing I am looking for? → name, one-line description, what problem it solves.
2. How do I use it? → install, quickstart, reference.

A third question, optional but commonly needed:

3. Does it work for my situation? → compatibility, critical limitations.

Everything else is either a pointer (`LICENSE`, `CONTRIBUTING`, issue tracker) or does not belong.

## Skeleton

Sections in order. Drop any section whose content would be empty rather than padding it; omission is more useful than `TBD`.

```
# <Project name>

<One-line tagline: name + what problem + for whom.>

[Optional: status badges row — CI, version, license, registry. Only if
the badge sources are automated and durable.]

## Install

<Single canonical install command. Plus upgrade and uninstall if
different from "reinstall the same way".>

<Compatibility line: host runtime version, required sibling tools,
OS constraints.>

## Usage

<Quickstart: minimum invocation that demonstrates value, 1 command +
1 short paragraph.>

[Optional: full subcommand / option reference. For small tools,
inline. For larger tools, link to docs/.]

## Limitations (only critical)

<Red-flag class only: genuinely broken cases, unresolved upstream
dependencies, known bugs that block the typical use case. Omit if
none exist. "Feature X is not yet supported" belongs in the issue
tracker, not here.>

## Pointers

- License: <SPDX or one-line "MIT — see LICENSE">.
- Contributing: <one-line "See CONTRIBUTING.md"> if a contributing file exists.
- Issues: <link to the repo's issue tracker>.
```

### README-specific additions (optional, if applicable)

These are surfaces a README often carries that other `docs/` pages typically do not:

- **Badges**: build / CI status, latest release version, license SPDX, package registry presence. Each badge must point at an authoritative source that updates on its own (shield.io against PyPI / GitHub Actions / Crates.io etc.). Hardcoded version strings as badges are a violation; use the registry-tracking shield.
- **Registry / install matrix**: a small table when the project is published to multiple ecosystems (PyPI + Homebrew + apt + Docker Hub). Each row links to the registry; do not duplicate install commands inline if the row's link reaches them.
- **One-line "See also" / comparison**: when the project is commonly confused with an alternative ("unlike X, this is for Y"). Single sentence; longer comparisons belong in a design issue or ADR.

For non-README `docs/**/*.md`, the skeleton's section 6 (Limitations) and the badges block are typically N/A.

## Forbidden content

Per `quality-list` `public-doc-durability`. The skeleton above structurally avoids each, but reiterating so the author cannot smuggle them in under the wrong section:

- Local filesystem paths (`~/`, `/Users/`, `/home/`, `/tmp/`, `/private/tmp/`, `/scratch/`).
- Version literals in prose (`v0.0.1 ships X`, `Status: v…`) — the manifest is the authoritative source.
- Roadmap / deferred-feature prose — the issue tracker is the authoritative source. Link to it.
- Changelog prose — `CHANGELOG.md` or release tags are the authoritative source.
- Progress-report / session-log narrative ("Initially we tried X but switched to Y").
- Implementation rationale dumps ("We chose hatchling because…") — belongs in ADR / commit body / design issue.
- File tree dumps — GitHub's repo viewer renders this.
- Reference / bibliography dumps of what the *author* read while building — visitor's next-link destinations only.
- Companion-tool specifics that name the maintainer's dotfile paths.

## Procedure

### 1. Confirm scope

- Target file path (`README.md` / `docs/<name>.md`).
- Whether an existing draft is being rewritten or this is a fresh write.
- Canonical install path (`uv tool install .` / `pip install` / `cargo install` / `npm install -g` / `brew install` / etc.).
- The project's authoritative sources for version (`pyproject.toml` / `Cargo.toml` / `package.json`), tracker, and CHANGELOG.

### 2. Draft each section

Walk the skeleton top to bottom. For each section, write the minimum content that answers the section's question; resist the urge to elaborate. If a section's content would be empty, drop the heading.

### 3. Cold-read pass

Re-read the draft as if you had never seen the project. Two checks:

- **Comprehensibility**: does a stranger learn what this project does and how to use it from sections 1–4 alone?

- **Forbidden content sweep**: run the `quality-list` `public-doc-durability` mechanical patterns against the draft:

  ```bash
  rg -n '(?:~/|/Users/|/home/|/tmp/|/private/tmp/|/scratch/)' <draft-path>
  rg -nP '\bv\d+\.\d+\.\d+\b' <draft-path>
  rg -nP '(?im)^#+\s*(Status|Roadmap|Deferred|Planned|Coming\s+soon|Recent\s+changes|Latest|What.?s\s+new|History|Background|Motivation|Why|Rationale|References?|Resources?|Bibliography|Further\s+reading|File\s+tree|Project\s+structure|Directory\s+layout|Acknowledg(e)?ments?)' <draft-path>
  rg -nP '(?i)\b(initially|originally|first[ -]?attempt|we (tried|chose|considered|settled|switched|moved|ended\s+up)|after (several|many)?\s*iteration)' <draft-path>
  ```

  Any hit is a candidate violation; resolve before step 4.

### 4. Show for approval

Present the laundered draft to the user verbatim before writing it to disk. Do not write without confirmation.

If the user requests changes, revise and re-show.

### 5. Write to disk

`Write` (or `Edit` for rewrites) the file. Stage with `git add` only when the user instructs; do not auto-commit.

## Notes

The skeleton is a contract between author and visitor; new section types are not added because the visitor's question set has not changed. If the project legitimately needs a new visitor-facing section (e.g., a SECURITY.md pointer), it goes under Pointers as a one-line link, not as a new top-level section.

When a visitor-facing concept genuinely needs a longer treatment (architecture overview, protocol spec, tuning guide), promote it to `docs/<topic>.md` and link from the README's Pointers. The README itself stays compact.
