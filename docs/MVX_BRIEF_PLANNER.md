# MVX Brief Planner boundary

Within MVX Ads Master, Auto Company is the planning authority for campaign briefs.

It receives campaign intent and constraints, forms the smallest useful expert squad using Auto Company's existing agents/skills, challenges assumptions, performs pre-mortem analysis and returns a structured production handoff.

The bridge is `scripts/mvx-brief-plan.sh`. It uses the canonical `scripts/core/engine-adapters.sh` interface and writes `request.json`, `plan.json`, `brief.md` and `engine-record.json` into the workflow-owned output directory.

This role is planning-only. It must not publish content, edit media, contact customers, claim provider success or manufacture performance evidence. MVX Ads Master records a separate human brief-approval gate before creative production can continue.
