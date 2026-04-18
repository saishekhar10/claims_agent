"""Insurance claims processing agent — ReAct orchestrator and claim prioritization."""

import from src.types {
    ClaimResult
}
import from src.tools {
    classify_document, extract_fields, validate_vin, reconcile_field,
    detect_duplicates, compose_customer_message
}

sem process_claim = """Process an insurance claim end-to-end and return a fully populated ClaimResult.

Inputs:
- claim_id: claim identifier string (e.g. "CLM-001")
- document_contents: JSON string — keys are filenames, values are objects with:
    "file_type": "pdf" | "image" | "text"
    "text": extracted or transcribed document text
    "handwriting_quality" (images only): {legibility_score, confidence_recommendation, ...}

Processing strategy — adapt based on what you find, do not assume a fixed structure:

1. CLASSIFY each document by calling classify_document(text) for each filename's text.

2. DETECT DUPLICATES by calling detect_duplicates(texts_json) with a JSON object mapping
   each filename to its text. Mark duplicates in DocumentsSummary.

3. EXTRACT FIELDS from each non-duplicate document using extract_fields(doc_type, text).
   - Set source = filename on each FieldResult.
   - For image documents: cap extracted confidence at handwriting_quality.confidence_recommendation.

4. VALIDATE VINs: for every VIN value found, call validate_vin(vin). Flag INVALID issues.

5. RECONCILE: if vin, date_of_loss, insurance_payout, or loan_balance appears in more than one
   document, call reconcile_field(field_data_json) with a JSON array of {value, confidence, source}.

6. IDENTIFY MISSING: required docs = {police_report, finance_agreement, settlement_breakdown}.
   Flag each missing type as an Issue with type MISSING.

7. DETERMINE STATUS:
   - COMPLETE: all 3 required docs present, all 4 key fields at MEDIUM or HIGH confidence, no conflicts.
   - INCOMPLETE: any required doc or field is absent.
   - NEEDS_REVIEW: conflicting field values, LOW confidence fields, or unresolvable issues.

8. NEXT ACTION:
   - INCOMPLETE or NEEDS_REVIEW and customer can help → call compose_customer_message(context),
     set next_action.type = MESSAGE_CUSTOMER, next_action.message = composed text.
   - Issues are internal only (conflicts, low confidence not fixable externally) → ESCALATE.
   - COMPLETE → FINALIZE.

9. Populate all ClaimResult fields carefully. Log every tool call in tools_used.""";

def process_claim(claim_id: str, document_contents: str) -> ClaimResult by llm(
    tools=[classify_document, extract_fields, validate_vin, reconcile_field, detect_duplicates, compose_customer_message]
);

sem prioritize_claims = """Sort a list of processed insurance claims by processing priority.
Input: JSON array of serialized ClaimResult objects.
Return JSON: {"processing_order": ["CLM-003", "CLM-001", ...], "rationale": "brief explanation"}.

Priority rules (highest urgency first):
1. NEEDS_REVIEW: unresolvable conflicts or LOW confidence — require immediate human attention.
2. INCOMPLETE: missing documents or fields — may be unblocked by contacting the customer.
3. COMPLETE: all data present and valid — lowest urgency, ready to finalize.
Within each group: more issues = higher priority.""";

def prioritize_claims(claim_results_json: str) -> str by llm();
