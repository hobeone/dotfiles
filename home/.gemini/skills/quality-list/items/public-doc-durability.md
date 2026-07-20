# Public-facing documentation durability

Public docs (`README.md`, `docs/**/*.md`, top-level `*.md` other than `CONTRIBUTING.md` / `LICENSE` / `NOTICE` / `CHANGELOG.md`) are a **visitor-facing surface**: the audience is a stranger who landed on the repo, not the author who built it. The audience determines what belongs:

- **What does this project do, and how do I use it** — yes.
- **Why we built it this way / what we tried first / what we read while building** — no, that goes to commit messages, PR descriptions, ADRs, design issues, or `CONTRIBUTING.md`.

LLM-drafted READMEs systematically violate this boundary in predictable ways. The author-vs-visitor distinction is the central principle; each concern condition below is a recurring instance.

**Concern conditions:**

- **Local filesystem paths in prose** — `~/`, `/Users/`, `/home/`, `/tmp/`, `/private/tmp/`, `/scratch/`, or any other absolute path that exists only on the maintainer's machine. These have no meaning to repo visitors. Replace with abstract descriptions ("`X` executable on your PATH") or generic placeholders (`body.md`, `<path>`).
- **Version literals in prose** — `v\d+\.\d+\.\d+` or "as of v…", "v0.0.1 ships X", "Currently v…", "Status: v…" when the project has an authoritative manifest (`pyproject.toml`, `Cargo.toml`, `package.json`, `mix.exs`, etc.). The prose drifts on every release; the manifest is single source of truth and the runtime `--version` reads from it.
- **Roadmap / deferred-feature prose** — "Deferred to v…", "Planned features", "Coming soon", "Will support X in vN" prose blocks when the project has an issue tracker. The tracker is single source of truth; duplicating it in README creates a second editing surface that decays. Link to the tracker instead of enumerating.
- **Changelog prose** — "Recent changes", "Latest: …", per-version bullet lists when `CHANGELOG.md` or release tags exist. Same duplication problem.
- **Point-in-time status sections** — "Currently v…", "Now at parity with X", "As of N tests passing", "Migration in progress" prose. These describe transient state and rot immediately after writing.
- **Progress-report / session-log narrative** — "Initially we tried X but switched to Y because …", "After several iterations we settled on …", "The first attempt failed, so …". README is product documentation, not a development diary. Change history lives in commit log, PR descriptions, or post-mortem notes — none of which are README.
- **Implementation rationale dumps ("Why" prose)** — "We chose hatchling because …", "We considered typer but went with argparse since …", "The trade-off was X vs Y, we picked Y". Belongs in ADRs, commit bodies, PR descriptions, or design issues — surfaces a reader actively *seeking* the why will discover. README explains **what** and **how to use**, not **why we picked**. Exception: a one-sentence "why" that frames the project's purpose against an alternative the reader is likely to confuse it with is fine ("unlike X, this is for Y"); anything longer is a decision record in the wrong place.
- **File tree dumps** — `src/`, `tests/`, `docs/` directory listings in README. GitHub's repo view already renders this; duplicating it ages the moment a file moves. Exception: a brief annotated tree that calls out *non-obvious* structure (e.g. "everything in `core/` is no-std; `host/` is the std-only host runtime") earns its place by adding information the file viewer alone cannot show.
- **Reference / bibliography dumps** — "Resources", "References", "Bibliography", "Further reading" sections that exhaustively enumerate what the *author* read while building. The link target audience is the visitor: every link should be one the visitor needs (install docs of dependencies, upstream protocol spec the project implements, related tools the visitor would compare against). Author-side acknowledgments ("inspired by", "thanks to") belong in `CONTRIBUTING.md` or a separate `NOTES.md` / `ACKNOWLEDGMENTS.md`.
- **Companion-tool / setup specifics that name the maintainer's stack** — "Reads the hook at `~/.claude/hooks/foo.sh`", "Registered in my `~/.tmux.conf`", named author / maintainer when the `pyproject` `authors` field already covers it. The README must work for a stranger who runs `git clone` and does not share the maintainer's dotfiles.

**Mechanical detection patterns:**

```bash
# Local paths.
rg -n '(?:~/|/Users/|/home/|/tmp/|/private/tmp/|/scratch/)' README.md docs/**/*.md
# Hardcoded version literals.
rg -nP '\bv\d+\.\d+\.\d+\b' README.md docs/**/*.md
# Author-side / progress-report / roadmap / changelog section headers.
rg -nP '(?im)^#+\s*(Status|Roadmap|Deferred|Planned|Coming\s+soon|Recent\s+changes|Latest|What.?s\s+new|History|Background|Motivation|Why|Rationale|References?|Resources?|Bibliography|Further\s+reading|File\s+tree|Project\s+structure|Directory\s+layout|Acknowledg(e)?ments?)' README.md docs/**/*.md
# Session-log narrative phrasings.
rg -nP '(?i)\b(initially|originally|first[ -]?attempt|we (tried|chose|considered|settled|switched|moved|ended\s+up)|after (several|many)?\s*iteration)' README.md docs/**/*.md
```

A hit on the first pattern is always a concern. Hits on the others are concerns when the listed authoritative source exists (manifest / tracker / CHANGELOG / tags / ADR / commit-message conventions), or when the section's content fits the author-side category above.

**N/A:** the doc surface is internal-only (private wiki, contributor-only design notes, ADRs that name a specific historical decision date), or the duplicated information has no authoritative source elsewhere (in which case the prose **is** the source of truth and rot is not a structural risk). `CHANGELOG.md` / release-note files are themselves the authoritative changelog source and N/A. `CONTRIBUTING.md` is the correct home for author-side acknowledgments and rationale that does not fit README.
