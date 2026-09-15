#!/usr/bin/env bash
# MVX Ads Master -> Auto Company brief-planning bridge.
# Uses Auto Company's existing engine-adapter boundary and expert-team repository context.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REQUEST_FILE="${1:-}"
OUTPUT_DIR="${2:-}"

if [ -z "$REQUEST_FILE" ] || [ -z "$OUTPUT_DIR" ]; then
  echo "usage: scripts/mvx-brief-plan.sh <request.json> <output-dir>" >&2
  exit 64
fi
REQUEST_FILE="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$REQUEST_FILE")"
OUTPUT_DIR="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$OUTPUT_DIR")"

python3 - "$REQUEST_FILE" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1])
if not p.is_file(): raise SystemExit("brief_request_not_found")
data=json.loads(p.read_text(encoding="utf-8"))
required=("brief_id","campaign_id","objective","deliverables")
missing=[k for k in required if not data.get(k)]
if missing: raise SystemExit("missing_fields:"+",".join(missing))
if not isinstance(data["deliverables"], list) or not data["deliverables"]: raise SystemExit("deliverables_must_be_non_empty_list")
PY

mkdir -p "$OUTPUT_DIR"
cp "$REQUEST_FILE" "$OUTPUT_DIR/request.json"

ENGINE="${MVX_BRIEF_ENGINE:-${ENGINE:-codex}}"
MODEL="${MVX_BRIEF_MODEL:-${MODEL:-}}"
MODEL_LABEL="${MODEL:-config-default}"
CLAUDE_BIN="${CLAUDE_BIN:-}"
CLAUDE_PERMISSION_MODE="${CLAUDE_PERMISSION_MODE:-acceptEdits}"
CODEX_BIN="${CODEX_BIN:-}"
CODEX_SANDBOX_MODE="${CODEX_SANDBOX_MODE:-workspace-write}"
CURSOR_BIN="${CURSOR_BIN:-}"
CYCLE_TIMEOUT_SECONDS="${MVX_BRIEF_TIMEOUT_SECONDS:-1200}"
CYCLE_TERM_GRACE_SECONDS=5
CYCLE_KILL_WAIT_SECONDS=5
RESOLVED_ENGINE_BIN=""

source "$PROJECT_DIR/scripts/core/engine-adapters.sh"
engine_adapter_validate
RESOLVED_ENGINE_BIN="$(engine_adapter_resolve)" || { engine_adapter_missing_dependency_message >&2; exit 69; }
export RESOLVED_ENGINE_BIN PROJECT_DIR ENGINE MODEL MODEL_LABEL CLAUDE_BIN CLAUDE_PERMISSION_MODE CODEX_BIN CODEX_SANDBOX_MODE CURSOR_BIN CYCLE_TIMEOUT_SECONDS CYCLE_TERM_GRACE_SECONDS CYCLE_KILL_WAIT_SECONDS

PLAN_PATH="$OUTPUT_DIR/plan.json"
BRIEF_PATH="$OUTPUT_DIR/brief.md"
PROMPT=$(cat <<EOF
You are Auto Company acting as the planning authority for MVX Ads Master.
This run is PLANNING ONLY. Do not publish, deploy, edit media, contact clients, or execute downstream production.

Read and apply the repository governance and expert methods in CLAUDE.md, .claude/agents/, and .claude/skills/team/SKILL.md. Form the smallest useful expert squad across Strategy, Product, Marketing, Operations, CFO, Research and Inversion. Challenge unsupported assumptions and force convergence.

Input request: $OUTPUT_DIR/request.json

Produce two files and nothing else outside $OUTPUT_DIR:
1. $PLAN_PATH — strict UTF-8 JSON.
2. $BRIEF_PATH — human-readable campaign brief.

plan.json schema requirements:
{
  "schema_version": 1,
  "brief_id": "same as request",
  "campaign_id": "same as request",
  "decision": "ready_for_human_review|needs_input|no_go",
  "objective": "specific outcome",
  "problem_statement": "...",
  "audience": {"primary": [], "secondary": [], "insights": []},
  "offer": {"value_proposition": "...", "proof_required": []},
  "constraints": [],
  "assumptions": [{"statement":"...","status":"unverified|supported","evidence_needed":"..."}],
  "risks": [{"risk":"...","severity":"low|medium|high|critical","mitigation":"..."}],
  "channels": [],
  "deliverables": [{"type":"...","count":1,"format":"...","acceptance_criteria":[]}],
  "creative_directions": [{"name":"...","insight":"...","hook_family":"...","reason":"..."}],
  "production_plan": [{"stage":"...","owner":"mvx-core|openchatcut|mvx-quality|mvx-social|mvx-operations|mvx-crm|human","inputs":[],"outputs":[],"gate":"..."}],
  "budget": {"currency":"EUR","hard_cap":null,"allocation":[]},
  "timeline": {"deadline":null,"milestones":[]},
  "measurement_plan": {"primary_kpis":[],"guardrails":[],"attribution_notes":[]},
  "legal_compliance_questions": [],
  "open_questions": [],
  "human_approval_required": true
}
Never invent performance evidence, market statistics, budget amounts, deadlines, legal clearance, customer facts or provider capabilities absent from request evidence. Unknown values must be null, [] or explicitly unverified.
EOF
)

engine_adapter_run "$PROMPT"
engine_adapter_extract_metadata

RECORD_PATH="$OUTPUT_DIR/engine-record.json"
engine_adapter_write_record "$RECORD_PATH" "$ADAPTER_STATUS"

if [ "$ADAPTER_STATUS" != "success" ]; then
  echo "brief_planning_engine_failed:$ADAPTER_SUBTYPE" >&2
  exit 70
fi

python3 - "$PLAN_PATH" "$OUTPUT_DIR/request.json" <<'PY'
import json, sys
from pathlib import Path
plan_path, request_path = map(Path, sys.argv[1:])
if not plan_path.is_file(): raise SystemExit("plan_json_missing")
plan=json.loads(plan_path.read_text(encoding="utf-8"))
req=json.loads(request_path.read_text(encoding="utf-8"))
required=("schema_version","brief_id","campaign_id","decision","objective","assumptions","risks","deliverables","production_plan","human_approval_required")
missing=[k for k in required if k not in plan]
if missing: raise SystemExit("invalid_plan_missing:"+",".join(missing))
if plan["brief_id"] != req["brief_id"] or plan["campaign_id"] != req["campaign_id"]: raise SystemExit("plan_identity_mismatch")
if plan["decision"] not in {"ready_for_human_review","needs_input","no_go"}: raise SystemExit("invalid_plan_decision")
if plan["human_approval_required"] is not True: raise SystemExit("human_gate_must_be_true")
PY

printf '%s\n' "$PLAN_PATH"
