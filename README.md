# Insurance Claims Processing Agent

An AI agent that processes total-loss vehicle insurance claims end-to-end — reading mixed document types, extracting and validating key fields, detecting conflicts, and deciding what to do next. Built entirely in Jac and byLLM on the Jaseci stack, with Python utilities for deterministic operations.

---

## Approach

The core problem is that claims arrive as a heterogeneous mix of documents — clean PDFs, scanned images, handwritten notes, customer emails — and the same field might appear in multiple documents with conflicting values, degraded legibility, or not at all. A fixed extraction pipeline fails here because the right behavior depends on what you actually find.

I built a ReAct agent that discovers and adapts rather than assuming structure. The agent classifies each document, runs duplicate detection, extracts fields with per-document confidence scoring, validates VINs, reconciles conflicts across sources, and decides the claim status — all through tool calls it chooses based on what it finds. A claim with only a customer email gets different treatment than one with four official documents and a duplicate settlement breakdown.

The language choice shaped the architecture. Jac's `by llm()` and `sem` annotations let me express tool semantics as meaning rather than prompt engineering. The agent's reasoning process and the tool contracts live in the same file, and the type system enforces the output schema without writing serialization code. The agent reasons about `DocType` and `Confidence` enums directly — not string outputs from prompt templates.

---

## Model

The agent uses **Claude Sonnet 4.6** (`claude-sonnet-4-6`) via the Anthropic API, configured at temperature 0.2 for consistent extraction behavior. All LLM tool calls — classification, field extraction, image transcription, and message composition — go through byLLM's ReAct loop using this model.

---

## Architecture

```
claims/CLM-001/
  police_report.pdf
  finance_agreement.png      ← scanned image
  adjuster_note.png          ← handwritten
  settlement_breakdown.pdf
        ↓
  Python utilities (pdf_reader, file_loader, handwriting_quality)
        ↓
  Jac agent — ReAct loop via byLLM
    classify_document × N
    detect_duplicates
    extract_fields × N
    validate_vin × M
    reconcile_field × K
    compose_customer_message (if needed)
        ↓
  outputs/CLM-001.json
```

The Python/Jac split is deliberate. Python handles file I/O, PDF extraction, and OpenCV-based image quality assessment — deterministic operations with no business going through an LLM. Jac handles orchestration, type definitions, and the agent loop. The boundary is: if it requires judgment, it's Jac; if it's data processing, it's Python.

---

## Tool Design

Eight tools, split by whether the operation requires reasoning or is deterministic.

**LLM tools** (no function body — meaning drives behavior via `sem`):

- `classify_document` — identifies document type from content. Returns a `DocType` enum. The sem describes structural characteristics of each type, not just labels to apply.
- `extract_fields` — extracts the four required fields plus any additional facts worth capturing. Confidence is two-factor: source quality (PDF vs scan vs handwritten vs self-reported) × extraction specificity (labeled field vs narrative inference vs approximate language). Final confidence is the lower of the two. A cleanly labeled field in a degraded scan is MEDIUM, not HIGH.
- `transcribe_image` — vision model call that converts document images to structured text. Preserves headers and columns, flags handwritten content with `HANDWRITTEN:` prefix, marks crossed-out text with `CROSSED OUT:` prefix.
- `compose_customer_message` — drafts the outgoing message when the agent needs something from the customer. Under 200 words, warm but specific about what's missing and why.

**Deterministic tools** (pure functions, fully auditable):

- `validate_vin` — regex check: exactly 17 alphanumeric characters, no I/O/Q. Returns a specific failure reason so the agent can explain what's wrong in the issue description.
- `reconcile_field` — given the same field from multiple sources, picks the highest-confidence value. Ties broken by source authority: police report > finance agreement > settlement breakdown > other. Flags conflicts explicitly rather than silently overriding.
- `detect_duplicates` — pairwise text similarity using difflib. Flags pairs above 85% similarity, notes whether a revision marker is present in the filename (`_v2`, `_final`, `_revised`).
- `assess_image_handwriting_quality` — OpenCV-based legibility scoring using contrast ratio (Otsu threshold), Laplacian sharpness variance, and Gaussian noise estimation. Returns a confidence recommendation that caps what the extraction step can claim for that document.

The split isn't about convenience — it's about auditability. Validation and reconciliation need to be reproducible and explainable. Classification and extraction need to handle variable document formats. Mixing those concerns produces a system where you can't trace why a field was rejected.

**What I decided not to build:** a dedicated date parser or dollar amount normalizer. The agent handles format variation naturally — "January 28th" vs "01/28/2026" get flagged as a format inconsistency, reconciled to the higher-confidence source, and logged. A parser would add complexity without adding judgment. Similarly, I didn't build a court-of-record for the customer message tone — the `compose_customer_message` sem handles this better than a template would.

---

## Handling Messy Input

Five claims, five different failure modes.

**CLM-001** — All docs present, all fields consistent across sources. Finalizes cleanly.

**CLM-002** — Police report missing. Customer emails provide officer details, but the agent correctly keeps the claim INCOMPLETE — it distinguishes between "customer told us" and "official document received." Pasted text doesn't substitute for the actual document.

**CLM-003** — VIN conflict between the finance agreement (`...182`) and every other document (`...127`). Both are valid 17-character VINs. The reconciler recommends the police report value but marks NEEDS_REVIEW rather than silently overriding a lender document. Also has a duplicate settlement breakdown — the original (ACV $24,100) superseded by a revised version (ACV $23,800) with a `REVISION NOTICE` stamp. Duplicate detector flagged 91.6% similarity and noted the `_v2` revision marker.

**CLM-004** — VIN `5YJ3E1EA7K` is consistently 10 characters across all four documents — a source error, not a cross-document conflict. The agent captures it exactly as written and flags INVALID. Settlement payout is "TBD — pending," extracted as LOW confidence with a separate MISSING issue. Also includes a tow receipt not in the spec — the agent classified it as `TOW_RECEIPT`, extracted the fees into `additional_facts`, and treated it as supplemental without being told to.

**CLM-005** — Date conflict: police report says 03/22/2026, settlement says 03/28/2026, customer corroborates 03/22. Reconciler picks 03/22 (police report authority) and flags the settlement date for correction. Finance agreement missing — customer thinks it was in the glove box. The settlement balance ($35,120.75) is used as a fallback, but the claim stays NEEDS_REVIEW: corroborating a value isn't the same as having the authoritative document. Police report also has a crossed-out officer name — transcribed as "CROSSED OUT: Det. Anthony Russo," assigned MEDIUM confidence; badge number stays HIGH.

---

## Interactive CLI

Single mode processes a claim and drops into an interactive loop when the agent needs customer input:

```bash
# Process a single claim (interactive if agent needs input)
jac src/main.jac ./claims CLM-002

# Batch display all processed claims
jac src/main.jac ./claims

# Re-run prioritization on existing outputs
jac src/main.jac ./claims prioritize
```

On first run with no existing output, the agent processes the claim automatically. On subsequent runs, it loads the existing JSON and displays it — no API calls until the user provides new input. The CLI uses `rich` for structured terminal output: colored status badges, a fields table with confidence indicators, a bordered panel for the agent's outgoing message, and a spinner during LLM calls.

When the agent needs more information, the menu appears:

```
[1] Paste document text      (type or paste, press Enter twice to finish)
[2] Provide a file path      (.pdf, .png, .jpg, .jpeg, or .txt)
[3] Provide a folder path    (adds all documents in folder)
[4] Escalate to human reviewer
[5] Exit
```

Option 2 runs the full preprocessing pipeline — PDFs get text extracted, images get transcribed via the vision model with handwriting quality assessment, text files are read directly. Image transcriptions are cached to `outputs/.cache/{claim_id}/` after the first run, so re-evaluation on a claim with multiple image documents doesn't re-run expensive vision calls on unchanged files.

---

## Output Format

Each claim produces a `ClaimResult` JSON:

```json
{
  "claim_id": "CLM-001",
  "status": "COMPLETE",
  "extracted_fields": {
    "vin": {
      "value": "1HGCM82633A004352",
      "confidence": "HIGH",
      "source": "police_report.pdf",
      "reason": ""
    },
    "date_of_loss": { "value": "02/14/2026", "confidence": "HIGH", "source": "police_report.pdf", "reason": "" },
    "insurance_payout": { "value": "$18,750.00", "confidence": "HIGH", "source": "settlement_breakdown.pdf", "reason": "" },
    "loan_balance": { "value": "$22,340.55", "confidence": "HIGH", "source": "finance_agreement.png", "reason": "" },
    "additional_facts": [
      { "key": "car_make", "value": "Honda", "confidence": "HIGH", "source": "police_report.pdf", "reason": "" },
      { "key": "odometer_reading", "value": "~47,200 mi", "confidence": "LOW", "source": "adjuster_note.png", "reason": "Approximate — odometer display was cracked." }
    ]
  },
  "documents": {
    "identified": [
      { "filename": "police_report.pdf", "doc_type": "POLICE_REPORT", "is_duplicate": false, "duplicate_of": null }
    ],
    "missing": [],
    "duplicates": []
  },
  "issues": [],
  "next_action": {
    "type": "FINALIZE",
    "message": null
  },
  "tools_used": [
    { "tool": "classify_document", "input": "police_report.pdf text", "result": "POLICE_REPORT" },
    { "tool": "validate_vin", "input": "1HGCM82633A004352", "result": "VALID" }
  ]
}
```

**Status values:** `COMPLETE` — all three required docs present, all four key fields at MEDIUM or higher, no conflicts. `INCOMPLETE` — a required document or field is absent. `NEEDS_REVIEW` — conflicting values, LOW confidence fields, or unresolvable issues requiring human judgment.

**Next action values:** `FINALIZE` — ready to process payout. `MESSAGE_CUSTOMER` — agent has drafted a message requesting specific missing items. `ESCALATE` — internal conflict not resolvable by the customer.

---

## Claim Prioritization

After batch processing, the agent ranks claims by how quickly they can be closed. Prioritization is fully LLM-driven — `prioritize_claims` is declared `by llm()` with no function body. All five serialized `ClaimResult` objects are passed as a JSON array, and the model reads through each one — status, issue count, issue types, what's blocking each claim — and returns a ranked list with a per-claim reason.

The `sem` annotation provides the ordering framework (COMPLETE first, then INCOMPLETE, then NEEDS_REVIEW, fewer issues rank higher within a group), but the reasoning about *why* CLM-005 ranks above CLM-004 — that CLM-005's blockers are partially corroborated and more resolvable while CLM-004 has two upstream blockers a claims processor can't unblock alone — is the model's judgment, not a sort function. The alternative would be a deterministic sort on status + issue count, which would be faster and cheaper but would miss that distinction.
<img width="1004" height="304" alt="Screenshot 2026-04-19 at 5 24 57 PM" src="https://github.com/user-attachments/assets/35c1fbe8-a1d6-4120-8fd3-d27de6ceac98" />


This is a throughput ordering: close what you can close now, then work toward harder cases. CLM-004 goes last not because it's less important but because both blockers require upstream fixes — a corrected VIN from the customer and a finalized ACV from the insurer — that a claims processor can't unblock alone.

---

## Key Decisions and Tradeoffs

**ReAct loop vs pipeline.** A hardcoded pipeline would be faster and cheaper per claim. The ReAct loop adapts to what the agent finds. A claim with only a customer email shouldn't run duplicate detection on a single document. A claim with no VIN conflict shouldn't call `reconcile_field` for it. CLM-004 includes a tow receipt that wasn't in the spec — the agent classified it, extracted from it, and treated it as supplemental without being told to. That flexibility has a cost: ~10–15 LLM calls per claim vs ~5 for a fixed pipeline.

**Two-factor confidence.** A single confidence axis misses important cases. A labeled VIN in a degraded scan is not the same as a labeled VIN in a clean PDF, and it's not the same as an approximate loan balance inferred from narrative text. Source quality and extraction specificity are independent axes, and the final confidence being the lower of the two reflects that both must hold for a value to be reliable.

**Flexible additional facts.** The assignment specifies four required fields. Every claim also contains variable data — car make/model, officer badge numbers, tow receipt line items, account numbers, GAP amounts. The `additional_facts: list[AdditionalFact]` schema captures anything relevant without schema changes. This means more complex output but a system that doesn't silently discard information it found.

**Type system via `sem`.** Jac's semantic annotations mean the agent reads the type system as meaning, not just structure. `Confidence.HIGH` is annotated with what actually makes a field high-confidence, not just a label. This paid off: the agent's confidence assignments tracked the intent of the annotations rather than requiring separate prompt tuning.

**OpenCV for handwriting quality.** Used instead of a dedicated OCR model because the goal is a heuristic confidence cap, not character-level accuracy. Laplacian sharpness variance, contrast ratio, and noise estimation give a fast, lightweight legibility score. A TrOCR model would give more accurate character recognition but adds a significant dependency for marginal gain at current scale.

---

## Challenges

**Re-evaluation latency.** The first version of the interactive loop was slow — providing new input triggered a full re-run of `preprocess_claim_folder`, meaning every image got re-transcribed via the vision model on every turn. For a claim with four image files, that's four expensive LLM calls that returned identical results to the previous turn.

Two fixes addressed this. First, image transcriptions are cached to `outputs/.cache/{claim_id}/{filename}.txt` after the first run. Before calling `transcribe_image()`, the code checks for the cache file and loads from disk if it exists — the vision model only runs once per image. The same caching applies to handwriting quality assessments (`{filename}.quality.json`).

Second, and more importantly, the interactive loop no longer calls `preprocess_claim_folder` at all on subsequent turns. On first run, the full preprocessed document contents (extracted PDF text, transcribed image text, quality scores) are saved to `outputs/{claim_id}.docs.json`. When the user provides new input, the loop loads this file, injects the new document into the existing dict, and calls the agent with the combined contents. The expensive preprocessing — PDF extraction and image transcription — never repeats. Only the agent's reasoning loop re-runs, which is unavoidable since it needs to reason over all documents including the new one.

This means re-evaluation time is bounded by the agent's ReAct loop (~8-10 LLM calls) rather than preprocessing + ReAct loop combined.

**byLLM ReAct loop termination.** Intermittently, the agent's ReAct loop terminates with `finish_tool() missing 1 required positional argument: 'final_output'`. This happens when the agent reaches the end of its reasoning but calls the internal finish tool without a required argument — a bug in byLLM's tool call handling for certain edge-case reasoning paths. It appeared most frequently on claims with multiple unresolvable issues (CLM-004 with invalid VIN + pending payout). The fix is a try/except around `process_claim()` that catches this error and retries once before surfacing it to the user.

**Jac/Python boundary for context managers.** The `rich` spinner (`console.status(...)`) is a Python context manager, but `process_claim()` is a Jac function. You can't wrap a Jac call inside a Python `with` block directly. The workaround is structuring the `::py::` blocks so the spinner starts before the Jac call and the status is displayed via a non-blocking approach — the spinner displays during the call rather than wrapping it.

---

## What I'd Do With More Time

**Advanced handwriting recognition.** The current OpenCV quality assessment is a heuristic — it scores legibility using contrast, sharpness, and noise but doesn't do actual character recognition. Replacing it with TrOCR or PaddleOCR (both open source) would give true character-level accuracy for handwritten documents, making confidence scoring for handwritten fields much more precise. PaddleOCR in particular handles degraded scans well and is lightweight enough to run without GPU.

**Fraud signal detection.** Three deterministic checks that would catch real patterns: policy issue date relative to date of loss (new policy + immediate total loss is a known signal), VIN appearing in multiple simultaneous claims, and payment status before the loss date. These are zero-LLM additions — pure rule evaluation on existing extracted fields.

**Parallel claim processing.** Claims are fully independent. Batch mode processes them serially. `asyncio.gather` across claims would cut batch time by the number of concurrent workers with no algorithmic changes.

**Separate preprocessing from reasoning.** The current ReAct loop handles both document I/O (classify, transcribe, extract) and reasoning (reconcile, validate, decide). At scale these should be separate stages — preprocessing runs as a parallel async pipeline feeding structured data to the agent, which then only does the reasoning steps. This cuts the per-claim ReAct loop from ~15 tool calls to ~5.

**State compliance layer.** Michigan has a 75% total loss threshold rule — if repair cost exceeds 75% of ACV, the vehicle is a total loss by statute. The agent doesn't validate this because the repair estimate isn't in the input documents for these claims. A production system needs state-specific rule evaluation and a compliance flags field in the output schema.

---

## Setup

```bash
conda create -n claims-agent python=3.12
conda activate claims-agent
pip install -r requirements.txt

# Add your Anthropic API key
echo "ANTHROPIC_API_KEY=your_key_here" > .env

# Process a single claim
jac src/main.jac ./claims CLM-001

# Batch display all processed claims
jac src/main.jac ./claims

# Re-run prioritization
jac src/main.jac ./claims prioritize
```

---

## Testing

```bash
# Unit tests — no API calls required
jac test tests/test_tools.jac

# Integration tests — requires API key
jac run tests/integration/test_classify.jac
jac run tests/integration/test_extract.jac
jac run tests/integration/test_transcribe.jac
```

21 unit tests cover the deterministic tools: VIN validation edge cases (forbidden characters, wrong length, empty input, special characters), field reconciliation (conflict detection, source authority tiebreaking, empty input handling), and duplicate detection (identical texts, revision markers, single-file edge case, multi-file pair count).

---

## File Structure

```
claims-agent/
├── src/
│   ├── types.jac                   # Enums, objects, sem annotations
│   ├── tools.jac                   # 4 LLM tools + 4 deterministic tools
│   ├── agent.jac                   # ReAct orchestrator + prioritization
│   ├── main.jac                    # CLI entry point (batch, single, interactive)
│   └── utils/
│       ├── pdf_reader.py           # PyMuPDF text extraction
│       ├── file_loader.py          # Folder walking, file inventory
│       └── handwriting_quality.py  # OpenCV legibility scoring
├── tests/
│   ├── test_tools.jac              # 21 unit tests
│   └── integration/                # LLM tool integration tests
├── outputs/                        # Per-claim JSON results
│   └── .cache/                     # Image transcription cache
├── ai_usage/                       # AI interaction logs
├── jac.toml                        # Model config (claude-sonnet-4-6, temp 0.2)
└── requirements.txt
```
