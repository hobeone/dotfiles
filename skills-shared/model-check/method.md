# Model Check — Method

Harness-neutral. An adapter `SKILL.md` loads this file and binds every
angle-bracketed verb used below to its own tools. Run every shell command in
this document with ⟨run⟩.

# Model Check: Verify a Model Exists Before Depending on It

A skill or script that names a model id (`gemini-3.8-flash-high`,
`opus-5.5-high`) is trusting that the id still exists. Ids are retired and
renamed; a stale one fails minutes into a long run, or gets quietly replaced
by whatever the CLI falls back to. This skill checks the id against what `agy`
actually offers **before** the work starts, and when it is missing, puts a
recommended alternative that really exists in front of the user.

**The rule:** an unavailable model is flagged to the user with a recommendation.
It is never silently substituted — not by this skill, and not by the caller.

---

## Resolve one model

```bash
⟨skill-dir⟩/scripts/resolve-model.sh [--refresh] [--json] REQUEST
```

`REQUEST` is any of:

| Form | Example | Meaning |
| :--- | :--- | :--- |
| Exact id | `gemini-3.8-flash-high` | Must be listed by `agy models`. |
| Display name | `Gemini 3.8 Flash (High)` | Lowercased, spaces to hyphens, parens dropped, then compared to ids and display names. |
| Auto | `auto:gemini-flash-high` | The **newest** listed model of that family, tier and effort. A tier or effort that does not exist is unavailable, not replaced by another. |

`auto:<family>-<tier>[-<effort>]`: family is `gemini`, `claude` or `gpt`
(`opus`, `sonnet`, `haiku` imply `claude`); tier is `flash-lite`, `flash`, `pro`,
`opus`, `sonnet`, `haiku` or `oss`; effort is `high`, `medium`, `low` or
`thinking`. Prefer `auto:` over a pinned id wherever "the current flash model"
is what you mean — it needs no edit when the version moves.

### Exit codes

| Code | Meaning | stdout | stderr |
| :--- | :--- | :--- | :--- |
| 0 | Available | the id to use (for `auto:`, the chosen id) | empty |
| 3 | Not available | the recommended id | `model-check: '<req>' is not available on agy. Recommended: <id> (<display>). Available: …` |
| 4 | Could not list models (agy missing, failed, or an empty list) | empty | why |
| 1 | Usage error | empty | usage |

Exit 3 and exit 4 are different facts. 3 means "this model is not offered"; 4
means "availability is **unknown**". Never report 4 as "unavailable", and never
treat 4 as "available".

`--json` prints `{requested, available, resolved, recommended, display, reason}`
on stdout for exits 0 and 3.

### The recommendation

For an unavailable request the script scores every listed model: same family
outweighs everything, then same tier, then same effort. Ties go to the newest
version, then the smaller id, so the same list always yields the same answer.
It is a suggestion for the user to accept or refuse, not a decision.

### The listing and its cache

The source of truth is `agy models`. The result is cached for
`MODEL_CHECK_TTL` seconds (default 21600, six hours) under
`${XDG_CACHE_HOME:-~/.cache}/model-check/`; `--refresh` bypasses the cache.
Only a good, non-empty listing is cached. If a model was just released and the
check says it is missing, re-run with `--refresh` before concluding it is.

---

## What a caller does with the result

1. **Exit 0** — proceed with the printed id.
2. **Exit 3** — stop. Show the user the requested id, the recommendation and
   the available list, and ask with ⟨ask-user⟩ whether to use the
   recommendation, pick another listed model, or cancel. Proceed only on their
   answer.
3. **Exit 4** — tell the user availability could not be verified and why. Offer
   to proceed unverified or to stop; do not assume either.

Only agy model ids are checked. Subagent tier aliases (`flash`, `flash_lite`,
`pro`) are not model ids and are out of scope.

---

## Checking a set of models

For a configuration block that names several ids, run `resolve-model.sh` once
per concrete id (the listing is cached, so only the first call pays for
`agy models`) and collect every non-zero result before asking: one question
that lists all the problems beats several in a row.
