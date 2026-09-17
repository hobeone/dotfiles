# Shared skills

Skills used by both Claude Code and agy. Each lives once here as a
harness-neutral core and is loaded by a thin adapter per harness.

## Layout

    skills-shared/<name>/          # the core: method.md plus any reference/, scripts/
    home/.claude/skills/<name>/    # Claude adapter
    home/.gemini/skills/<name>/    # agy adapter

Each adapter directory contains its own `SKILL.md` and one relative symlink per
top-level core entry, e.g. `method.md -> ../../../../skills-shared/<name>/method.md`.
Linking entries individually (not one `core/` link) keeps paths like
`~/.gemini/skills/<name>/reference/...` valid for existing callers.

## Rules

- **No harness vocabulary in the core.** No Claude Code tool names, whether
  bare (`invoke_subagent`, `AskUserQuestion`, ...) or backticked
  (`` `Bash` ``, `` `Read` ``, `` `Edit` ``, `` `Write` ``, `` `Agent` ``,
  `` `Workflow` ``, `` `Grep` ``, `` `Glob` ``, `` `WebFetch` ``,
  `` `WebSearch` ``, `` `TodoWrite` ``, `` `Skill` ``, `` `NotebookEdit` ``,
  `` `AskUserQuestion` ``); no agy tool names (`view_file`, `code_search`,
  `find_by_name`, `grep_search`, `list_dir`, `manage_subagents`,
  `define_subagent`, `replace_file_content`, `multi_replace_file_content`,
  `write_to_file`, `read_url_content`, `search_web`, ...); and no harness home
  paths. Write a `⟨verb⟩` instead, and cite companion skills by name.
- **Verb tokens are well-formed.** Every `⟨...⟩` token in a core file must
  match `⟨[a-z][a-z-]*⟩` — lowercase, hyphen-separated, no placeholders.
- **Adapters bind every verb the core uses, and nothing else.** One
  `## Harness mapping` table whose rows start with `` | `⟨verb⟩` ``.
- **Adapters hold no method.** Every `## ` heading in an adapter `SKILL.md`
  must be one of `Harness mapping`, `Model routing`, `Harness notes`,
  `Verified call shape`; no `## Phase` or `### Angle` heading may appear.
- **Callers cite phases by name**, never by number.

`tests/test_skills_shared.sh` enforces all of the above: both harness
tool-name sets, verb-token well-formedness, verb binding in both directions
(nothing missing, nothing unused), the allowed adapter headings, and that
every adapter symlink resolves relative into the matching core entry with no
stray adapter-only links.

## Migrating a forked skill

1. `git mv` the more current copy's files into `skills-shared/<name>/`
   (`SKILL.md` becomes `method.md`); fold in anything only the other copy has.
2. Replace tool names and harness paths with verbs.
3. Replace both harness directories with an adapter `SKILL.md` plus links.
4. Run `bash tests/test_skills_shared.sh`.
