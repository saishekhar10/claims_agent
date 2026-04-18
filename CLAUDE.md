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
