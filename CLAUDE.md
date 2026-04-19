# Claims Agent Project Context

## Project Overview

AI insurance claims processing agent built with Jac (jaseci.org) + Python utilities.

**Backend:** Claude Sonnet 4.6 via Anthropic API  
**Task:** Extract, validate, and assess insurance claim documents (PDFs, scanned images, text files)  
**Input:** Claims folder with mixed document types  
**Output:** Structured JSON with extracted fields, validation issues, confidence scores, and recommended actions

## Architecture

### Jac + Python Hybrid
- **Jac:** Orchestration, type definitions, agent logic, ReAct loops, tool calling
- **Python:** File I/O, PDF extraction, image processing, deterministic utilities

### Project Structure
claims-agent/
├── src/
│   ├── types.jac          — Type system (enums, objects, semantic annotations)
│   ├── tools.jac          — Tool definitions (4 LLM + 3 deterministic)
│   ├── agent.jac          — Agent orchestrator (ReAct loop)
│   ├── main.jac           — Entry point (batch, single, interactive modes)
│   └── utils/
│       ├── pdf_reader.py           — PDF text extraction
│       ├── file_loader.py          — Dynamic folder loading
│       └── handwriting_quality.py  — Image quality assessment
├── tests/
│   ├── test_tools.jac     — 21 unit tests (deterministic tools)
│   └── integration/       — Integration tests (LLM tools)
├── jac.toml               — Jac configuration
├── requirements.txt       — Dependencies
└── outputs/               — Results (JSON per claim)

## Completed Components

### Type System (src/types.jac)

**Enumerations:**
- `Confidence` (HIGH/MEDIUM/LOW) — Two-factor: source quality × extraction specificity
- `DocType` — Police report, finance agreement, settlement breakdown, adjuster note, tow receipt, customer email, unknown
- `ClaimStatus` (COMPLETE/INCOMPLETE/NEEDS_REVIEW) — Completeness assessment
- `ActionType` (FINALIZE/MESSAGE_CUSTOMER/ESCALATE) — Next steps
- `IssueType` (INCONSISTENCY/MISSING/INVALID/LOW_CONFIDENCE) — Problem categories

**Data Objects:**
- `FieldResult` — Single extracted field (value, confidence, source, reason)
- `ExtractedFields` — 4 required fields (VIN, date of loss, insurance payout, loan balance) + flexible facts dict
- `DocumentInfo` — File metadata and classification
- `DocumentsSummary` — Inventory of identified/missing/duplicate documents
- `Issue` — Flagged problems with details
- `NextAction` — Recommended action + customer message
- `ToolUsage` — Audit log of tool calls
- `ClaimResult` — Complete claim assessment (output format)

### Tool Suite (src/tools.jac)

**LLM Tools** (Claude via byLLM — no function bodies, semantic-driven):
1. `classify_document(text: str) -> DocType` — Identify document type
2. `extract_fields(doc_type: DocType, text: str) -> ExtractedFields` — Extract required fields + flexible facts
3. `transcribe_image(image: Image) -> str` — Convert image to text (preserves structure, flags handwriting)
4. `compose_message(claim_context: str) -> str` — Generate customer message (<200 words)

**Deterministic Tools** (Pure functions):
5. `vin_validator(vin: str) -> dict` — Regex: 17 alphanumeric, no I/O/Q
6. `field_reconciler(field_values: str) -> str` — Resolve conflicts, pick highest confidence
7. `duplicate_detector(texts: list[str]) -> str` — Pairwise similarity >85%, flag duplicates
8. `assess_image_handwriting_quality(image_path: str) -> dict` — OpenCV-based legibility scoring

### Python Utilities

**pdf_reader.py:**
- `extract_text_from_pdf(pdf_path: str) -> str` — PyMuPDF text extraction

**file_loader.py:**
- `load_claim_folder(folder_path: str) -> dict` — Walk folder, return file inventory
- `read_text_file(file_path: str) -> str` — Read text files

**handwriting_quality.py:**
- `assess_handwriting_quality(image_path: str) -> dict` — Contrast, blur, degradation analysis
- Returns legibility score (0-100) + confidence recommendation

### Testing

**Unit Tests (tests/test_tools.jac):** 21 passing tests for deterministic tools

**Integration Tests (tests/integration/):**
- `test_classify.jac` — Document classification on real police report text
- `test_extract.jac` — Field extraction with HIGH confidence on clean data
- `test_transcribe.jac` — Image-to-text on actual claim PNG

## Key Design Principles

**Flexibility:** Claims folder path provided at runtime. Agent discovers data dynamically, not hardcoded.

**ReAct Loop:** Agent decides which tools to call based on what it finds. Not a fixed pipeline.

**Flexible Facts:** 4 required fields + `additional_facts` dict for variable data (car make, weather, incident details, etc.)

**Confidence Scoring:** Two-factor assessment — source quality (PDF/scan/handwritten) × extraction specificity (labeled/inferred/approximate).

**Handwriting Handling:** OpenCV-based legibility assessment. Explicit confidence downgrade for unclear characters.

**Deterministic + LLM Split:** Validation and reconciliation are deterministic (auditable, reproducible). Classification and extraction are LLM-powered (flexible, context-aware).

## Configuration

- **Model:** claude-sonnet-4-6 (Anthropic API)
- **Temperature:** 0.2 (deterministic)
- **Max Tokens:** 4000 per call
- **Environment:** Python 3.12, Jac 0.14.0, conda environment: claims-agent

## References

- Jac documentation: https://docs.jaseci.org/
- Agentic tutorial: https://docs.jaseci.org/tutorials/ai/agentic/
- byLLM tool calling: https://docs.jaseci.org/reference/plugins/byllm/#tool-calling-react

<!-- dgc-policy-v11 -->
# Dual-Graph Context Policy

This project uses a local dual-graph MCP server for efficient context retrieval.

## MANDATORY: Always follow this order

1. **Call `graph_continue` first** — before any file exploration, grep, or code reading.

2. **If `graph_continue` returns `needs_project=true`**: call `graph_scan` with the
   current project directory (`pwd`). Do NOT ask the user.

3. **If `graph_continue` returns `skip=true`**: project has fewer than 5 files.
   Do NOT do broad or recursive exploration. Read only specific files if their names
   are mentioned, or ask the user what to work on.

4. **Read `recommended_files`** using `graph_read` — **one call per file**.
   - `graph_read` accepts a single `file` parameter (string). Call it separately for each
     recommended file. Do NOT pass an array or batch multiple files into one call.
   - `recommended_files` may contain `file::symbol` entries (e.g. `src/auth.ts::handleLogin`).
     Pass them verbatim to `graph_read(file: "src/auth.ts::handleLogin")` — it reads only
     that symbol's lines, not the full file.
   - Example: if `recommended_files` is `["src/auth.ts::handleLogin", "src/db.ts"]`,
     call `graph_read(file: "src/auth.ts::handleLogin")` and `graph_read(file: "src/db.ts")`
     as two separate calls (they can be parallel).

5. **Check `confidence` and obey the caps strictly:**
   - `confidence=high` -> Stop. Do NOT grep or explore further.
   - `confidence=medium` -> If recommended files are insufficient, call `fallback_rg`
     at most `max_supplementary_greps` time(s) with specific terms, then `graph_read`
     at most `max_supplementary_files` additional file(s). Then stop.
   - `confidence=low` -> Call `fallback_rg` at most `max_supplementary_greps` time(s),
     then `graph_read` at most `max_supplementary_files` file(s). Then stop.

## Token Usage

A `token-counter` MCP is available for tracking live token usage.

- To check how many tokens a large file or text will cost **before** reading it:
  `count_tokens({text: "<content>"})`
- To log actual usage after a task completes (if the user asks):
  `log_usage({input_tokens: <est>, output_tokens: <est>, description: "<task>"})`
- To show the user their running session cost:
  `get_session_stats()`

Live dashboard URL is printed at startup next to "Token usage".

## Rules

- Do NOT use `rg`, `grep`, or bash file exploration before calling `graph_continue`.
- Do NOT do broad/recursive exploration at any confidence level.
- `max_supplementary_greps` and `max_supplementary_files` are hard caps - never exceed them.
- Do NOT dump full chat history.
- Do NOT call `graph_retrieve` more than once per turn.
- After edits, call `graph_register_edit` with the changed files. Use `file::symbol` notation (e.g. `src/auth.ts::handleLogin`) when the edit targets a specific function, class, or hook.

## Context Store

Whenever you make a decision, identify a task, note a next step, fact, or blocker during a conversation, call `graph_add_memory`.

**To add an entry:**
```
graph_add_memory(type="decision|task|next|fact|blocker", content="one sentence max 15 words", tags=["topic"], files=["relevant/file.ts"])
```

**Do NOT write context-store.json directly** — always use `graph_add_memory`. It applies pruning and keeps the store healthy.

**Rules:**
- Only log things worth remembering across sessions (not every minor detail)
- `content` must be under 15 words
- `files` lists the files this decision/task relates to (can be empty)
- Log immediately when the item arises — not at session end

## Session End

When the user signals they are done (e.g. "bye", "done", "wrap up", "end session"), proactively update `CONTEXT.md` in the project root with:
- **Current Task**: one sentence on what was being worked on
- **Key Decisions**: bullet list, max 3 items
- **Next Steps**: bullet list, max 3 items

Keep `CONTEXT.md` under 20 lines total. Do NOT summarize the full conversation — only what's needed to resume next session.
