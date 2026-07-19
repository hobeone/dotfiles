# License compliance and attribution for ported code

Code reused from an external project — whether copied verbatim, ported line-for-line into a different language, or transcribed with cosmetic changes (renames, rephrased structure, dropped scaffolding) — carries the source project's license obligations into the derivative. The audit asks two distinct questions:

1. **Is the source license compatible with this project's license?** The combinatorics of permissive ↔ permissive, permissive ↔ copyleft, and proprietary ↔ anything are well-defined; the concern is forgetting to do the check, not picking the wrong answer once you look.
2. **Are the upstream license's specific obligations satisfied?** Common requirements: retain copyright notice, name the source project, list modifications, propagate any upstream NOTICE-file content, retain license text. The exact set varies (Apache-2.0 § 4(b)–(d) is the most-discussed reference, MIT requires retention of copyright + permission text, BSD has the no-endorsement clause, etc.).

**Detection.** The structural signals that a diff contains ported code:

- A comment that says "ported from", "derived from", "based on", "from $project", or names another project as source.
- New identifiers, function shapes, or algorithm structure that match a known upstream pattern that the author admits to having referenced during research / planning. (When research surfaced a specific external implementation as a reference and the diff structurally mirrors it, treat as a port even if no comment says so explicitly.)
- A research-phase note ("ported $func from $project") that has no matching attribution comment in the diff.

**Verification, when a port is identified.**

- **License compatibility.** Confirm the source license. Permissive → permissive (Apache-2.0, MIT, BSD, ISC, etc.) is generally fine with attribution; copyleft (GPL, AGPL, MPL, EPL, LGPL) into a permissive project usually is *not*. If unsure, escalate.
- **Attribution surface.** A comment block on or above the ported declarations naming: (1) the upstream project, (2) the source file / URL, (3) the upstream copyright line, (4) the license name and version. For a single helper an in-source comment is sufficient; for many helpers from one source, a top-level attribution surface (`THIRD_PARTY.md`, `NOTICE`, etc.) may be cleaner.
- **Modifications enumerated.** Apache-2.0 § 4(b) and the MIT/BSD "preserve the notice" lanes both expect the reader to be able to tell what the derivative changed. Either an inline "Notable changes from upstream" list or a clear "ported as-is, modulo language rephrase" statement.
- **Upstream NOTICE / NOTICE-equivalent.** If the upstream license triggers a NOTICE-propagation clause (Apache-2.0 § 4(d) is the common one), **fetch the upstream NOTICE file and verify it exists before claiming compliance**. A NOTICE file in the derivative that cites a non-existent upstream NOTICE is worse than none — it implies upstream content the derivative cannot reproduce.

**Concern conditions:**

- Diff contains ported code from an external project but no attribution comment / file names the upstream project, source location, upstream copyright, and license.
- Research notes / commit messages name an external project as source, but the in-source attribution does not.
- Upstream license is incompatible with this project's license (e.g., GPL code in an Apache-2.0 project) and the diff does not address the conflict.
- Modifications relative to upstream are not enumerated, and the upstream license requires marking changed files (e.g., Apache-2.0 § 4(b)).
- A NOTICE / THIRD_PARTY file in the diff claims to mirror an upstream NOTICE, but the upstream does not have one (verified by fetching it from the canonical source).
- The naming-as-claim concern from item 11 also fires: the ported code's name asserts a property not in the upstream (e.g., calling a U(2)-sampling helper "Haar"), which can imply distributional guarantees the port does not provide.

**N/A:** the diff contains no ported code from an external project (fresh design or trivial idiom).
