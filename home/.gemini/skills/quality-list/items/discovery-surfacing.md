# Discovery surfacing (plan-vs-actual)

If a research plan exists for this work, every divergence between the plan and the implementation must trace to one of:

- A `confirmed` outcome of an `inconclusive` item's `probe` (with the resolved branch followed)
- A `deferred` item reaching its `resolution-point`
- An explicit re-plan note added to the plan or surfaced to the user

Silent ad-hoc divergence — patching an unexpected fact during implementation without recording how it relates to the plan — is a concern. The plan's `Inconclusive / Deferred items` section is the only sanctioned channel for mid-implementation surprises.

**Plan-enumeration completeness.** When the plan enumerates discrete artifacts to produce — test sub-cases, error variants, files to add, API methods to expose, fixture builders, sub-tasks in a checklist — every listed item must have a corresponding artifact in the diff.

The default audit semantics for a plan enumeration is **exhaustive**: an N-item list demands N matching artifacts in the diff, mapped 1-to-1. Plan authors who intend a list to be **representative** (a sample, not the full set) must declare that inline (`(representative)` / `(illustrative)` / equivalent annotation on the list). Without an explicit annotation, the audit treats the list as exhaustive.

This is the inverse failure mode of the silent-extra-divergence concern above: instead of the implementation adding work the plan did not anticipate, the implementation silently ships fewer artifacts than the plan promised. Both are plan-vs-actual concerns and both must be surfaced to the user before merge — either by completing the missing artifacts, marking them deferred with a follow-up, or annotating the plan list as representative.

**Concern conditions:**

- Implementation diverges from the plan and the divergence is not traceable to a listed `inconclusive` probe outcome, a `deferred` resolution, or an explicit re-plan note
- Plan had `Inconclusive` items but none were probed during implementation (verify whether the probe was actually needed; if yes, this is incomplete work)
- Plan was retroactively edited to match the implementation without user-visible surfacing
- Plan enumerated N discrete artifacts (without `(representative)` annotation) but the diff contains fewer than N, with no deferral note explaining the gap

**N/A:** there is no plan (ad-hoc edit, typo fix, no preceding research phase).
