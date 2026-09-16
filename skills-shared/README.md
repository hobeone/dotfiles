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

- **No harness vocabulary in the core.** No tool names (`run_subagent`,
  `view_file`, `AskUserQuestion`, ...) and no harness home paths. Write a
  `⟨verb⟩` instead, and cite companion skills by name.
- **Adapters bind every verb the core uses, and nothing else.** One
  `## Harness mapping` table whose rows start with `` | `⟨verb⟩` ``.
- **Adapters hold no method.** Frontmatter, bindings, model routing, and
  harness-only notes only.
- **Callers cite phases by name**, never by number.

`tests/test_skills_shared.sh` enforces the first two rules and the links.

## Migrating a forked skill

1. `git mv` the more current copy's files into `skills-shared/<name>/`
   (`SKILL.md` becomes `method.md`); fold in anything only the other copy has.
2. Replace tool names and harness paths with verbs.
3. Replace both harness directories with an adapter `SKILL.md` plus links.
4. Run `bash tests/test_skills_shared.sh`.
