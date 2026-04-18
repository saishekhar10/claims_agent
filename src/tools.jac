"""Tools for the insurance claims processing agent."""

import from .types {
    DocType,
    ExtractedFields,
    FieldResult,
    Confidence
}
import from byllm.lib { Image }
import re;
import json;
import from difflib { SequenceMatcher }

# ── LLM Tools ─────────────────────────────────────────────────────────────────

sem classify_document = """Identify the insurance document type from its text content. Use these characteristics:
- POLICE_REPORT: official letterhead (e.g. 'POLICE DEPARTMENT', 'SHERIFF'), report number, officer name/badge, sections like 'INCIDENT INFORMATION', 'VEHICLE INFORMATION', date/time/location of accident.
- FINANCE_AGREEMENT: lender name, loan account number, borrower name, 'Monthly Payment', 'Interest Rate', 'Outstanding Balance', 'Payoff Amount', vehicle as collateral.
- SETTLEMENT_BREAKDOWN: insurance company name, 'Actual Cash Value', 'Deductible', 'Net Payment to Insured', 'Total Loss', itemized calculation of payout.
- ADJUSTER_NOTE: shorter informal document, 'Adjuster:', 'Inspection Date', handwritten-style damage notes, repair estimates, field observations.
- TOW_RECEIPT: towing company name, 'Tow Charge', 'Storage Fee', vehicle description, pickup/drop-off location, itemized receipt format.
- CUSTOMER_EMAIL: email headers (From:, To:, Subject:, Date:), conversational prose, customer name/contact info, references a prior request or claim number.
- UNKNOWN: none of the above match clearly.
When in doubt, use UNKNOWN rather than guessing.""";

def classify_document(text: str) -> DocType by llm();

sem extract_fields = """Extract the four key insurance claim fields from document text. Also capture any additional relevant facts.

For each of the four required fields, assign confidence using BOTH factors below — final confidence is the LOWER of the two:
  Factor 1 — Source quality:
    HIGH = clean PDF with printed text
    MEDIUM = scanned image via OCR or typed but degraded
    LOW = handwritten, heavily degraded, or self-reported by customer
  Factor 2 — Extraction specificity:
    HIGH = field is explicitly labeled (e.g. 'VIN: 1HGCM82633A004352')
    MEDIUM = value inferred from narrative context (e.g. 'the vehicle, a 2020 Honda with VIN ...')
    LOW = value is approximate, inferred, or ambiguous (e.g. 'approximately $18,000')

Always set reason when confidence is MEDIUM or LOW — explain briefly why.

Required fields:
- vin: 17-char alphanumeric string. Look for 'VIN', 'Vehicle Identification Number'. Capture exactly as written — do not correct.
- date_of_loss: date the incident occurred. Look for 'Date of Incident', 'Date of Loss', 'Accident Date'. Format as found.
- insurance_payout: the total settlement payout. Look for 'Net Payment', 'Total Payout', 'Settlement Amount', 'Net to Insured'. Include dollar sign if present.
- loan_balance: outstanding loan balance. Look for 'Outstanding Balance', 'Remaining Principal', 'Payoff Amount'. Include dollar sign if present.

Set field to None if not found in this document — do not guess.

For additional_facts, capture any other useful information as key-value pairs:
  Examples: car_make, car_model, car_year, incident_location, weather_conditions, officer_name, report_number,
  lender_name, account_number, adjuster_name, claimant_name, policy_number, total_loss_value, deductible.
  Use snake_case keys. Values are FieldResult objects — confidence reflects the same two-factor logic above.""";

def extract_fields(doc_type: DocType, text: str) -> ExtractedFields by llm();

sem transcribe_image = """Transcribe all visible text from this document image.
Preserve document structure: keep headers, labels, columns, and section breaks using newlines.
For handwritten text, prefix with 'HANDWRITTEN: ' before the content.
For crossed-out or struck-through text, prefix with 'CROSSED OUT: '.
For text that is unclear or illegible, write '[unclear]' in place of it.
For signatures or initials, write '[signature]' or '[initials]'.
For stamps or rubber stamps, prefix with 'STAMP: '.
Return the full transcription as a single string. Do not summarize — transcribe everything visible.""";

def transcribe_image(image: Image) -> str by llm();

sem compose_customer_message = """Write a professional, empathetic insurance claims message to a customer. Under 200 words.
The claim_context string describes the claim ID, what is missing or problematic, and what is needed from the customer.
Structure:
1. Open by acknowledging their claim and referencing the claim ID.
2. Clearly state what specific documents or information are needed, and why each is required.
3. Provide a polite closing with a call to action (e.g. reply to this email, upload to portal).
Tone: professional but warm. Avoid jargon. Do not be accusatory. Do not promise a specific resolution timeline.""";

def compose_customer_message(claim_context: str) -> str by llm();

# ── Deterministic Tools ────────────────────────────────────────────────────────

"""Validate a Vehicle Identification Number (VIN).
Rules: exactly 17 characters, alphanumeric only, no letters I/O/Q (excluded from VINs due to visual ambiguity with 1/0).
Input vin is stripped of whitespace and uppercased before validation.
Returns 'VALID' on success, or 'INVALID: <specific reason>' on failure — check the reason to understand what to fix."""
def validate_vin(vin: str) -> str {
    if not vin {
        return "INVALID: empty value";
    }
    vin_upper = vin.strip().upper();
    if len(vin_upper) != 17 {
        return f"INVALID: must be exactly 17 characters, got {len(vin_upper)}";
    }
    forbidden = re.findall(r'[IOQ]', vin_upper);
    if forbidden {
        found = ", ".join(sorted(set(forbidden)));
        return f"INVALID: contains forbidden letter(s) {found} — I, O, Q are not used in VINs";
    }
    if not re.match(r'^[A-HJ-NPR-Z0-9]{17}$', vin_upper) {
        return "INVALID: contains non-alphanumeric characters";
    }
    return "VALID";
}

"""Compare the same field value across multiple source documents and recommend the best value.
Input: JSON array where each element has keys: 'value' (str), 'confidence' (str: HIGH/MEDIUM/LOW), 'source' (str filename).
Returns JSON with: 'recommended_value', 'chosen_source', 'confidence', 'has_conflict' (bool), 'conflicts' (list), 'notes'.
Selection logic: highest confidence wins. Ties broken by source authority (police_report > finance_agreement > settlement_breakdown > other).
Conflict detected when normalized values differ across entries. Use this before accepting any field with multiple sources."""
def reconcile_field(field_data_json: str) -> str {
    output: str = "";
    ::py::
import json as _json

def _conf_rank(c):
    return {"HIGH": 3, "MEDIUM": 2, "LOW": 1}.get(str(c).upper(), 0)

def _src_rank(s):
    sl = (s or "").lower()
    if "police" in sl: return 4
    if "finance" in sl: return 3
    if "settlement" in sl: return 2
    return 1

entries = _json.loads(field_data_json)
if not entries:
    output = _json.dumps({"error": "empty input"})
else:
    normed_vals = {e.get("value", "").strip().upper() for e in entries if e.get("value")}
    has_conflict = len(normed_vals) > 1

    ranked = sorted(
        entries,
        key=lambda e: (_conf_rank(e.get("confidence")), _src_rank(e.get("source"))),
        reverse=True
    )
    best = ranked[0]

    conflicts = []
    if has_conflict:
        for e in entries:
            if e.get("value", "").strip().upper() != best.get("value", "").strip().upper():
                conflicts.append({
                    "value": e.get("value"),
                    "source": e.get("source"),
                    "confidence": e.get("confidence")
                })

    if has_conflict:
        notes = f"Conflict detected: {len(normed_vals)} distinct values. Recommending highest-confidence source."
    elif len(entries) > 1:
        notes = f"Consistent across {len(entries)} sources."
    else:
        notes = "Single source."

    output = _json.dumps({
        "recommended_value": best.get("value"),
        "chosen_source": best.get("source"),
        "confidence": best.get("confidence"),
        "has_conflict": has_conflict,
        "conflicts": conflicts,
        "notes": notes
    })
    ::py::
    return output;
}

"""Detect duplicate documents by comparing text similarity between all file pairs in a claim.
Input: JSON object mapping filename (str) to extracted text content (str).
Returns JSON with: 'pairs' list of {file_a, file_b, similarity_pct, is_duplicate, notes}.
Pairs with similarity_pct > 85 are flagged as duplicates. Revision markers in filenames (v2, final, updated, copy, revised) are noted as supporting evidence.
Truncates text to 3000 chars per file for performance. Use after all documents in a claim have been extracted."""
def detect_duplicates(texts_json: str) -> str {
    output: str = "";
    ::py::
import json as _json
from difflib import SequenceMatcher as _SM
import re as _re

def _has_revision_marker(name):
    return bool(_re.search(r'_v\d+|v\d+\.|_final|_updated|_copy|_revised', name.lower()))

docs = _json.loads(texts_json)
filenames = list(docs.keys())
pairs = []

for i in range(len(filenames)):
    for j in range(i + 1, len(filenames)):
        fa, fb = filenames[i], filenames[j]
        ta = str(docs.get(fa, ""))[:3000]
        tb = str(docs.get(fb, ""))[:3000]
        ratio = _SM(None, ta, tb).ratio()
        sim_pct = round(ratio * 100, 1)
        is_dup = sim_pct > 85.0
        notes = ""
        if is_dup:
            if _has_revision_marker(fa) or _has_revision_marker(fb):
                notes = "Filename revision marker detected — likely a revised version of the same document."
            else:
                notes = "Near-identical content with no revision marker — likely an exact duplicate."
        pairs.append({
            "file_a": fa,
            "file_b": fb,
            "similarity_pct": sim_pct,
            "is_duplicate": is_dup,
            "notes": notes
        })

output = _json.dumps({"pairs": pairs})
    ::py::
    return output;
}

"""Assess handwriting legibility from an image file using OpenCV.
Input: Path to an image file (PNG, JPG).
Returns JSON string with:
- legibility_score (0-100): How readable the handwriting is
- confidence_recommendation: "HIGH", "MEDIUM", or "LOW"
- contrast_ratio: Ink vs background contrast
- degradation_score (0-100): Image degradation level (0 = clean)
- blur_detected: True if the image is out of focus
- overall_quality (0-100): Composite quality score
- details: Human-readable explanation of any quality issues found
Usage: Call this before extract_fields on handwritten image documents.
If legibility_score < 50 or confidence_recommendation is LOW, treat all extracted fields from this document as LOW confidence."""
def assess_image_handwriting_quality(image_path: str) -> str {
    output: str = "";
    ::py::
import json as _json
import sys as _sys
_sys.path.insert(0, "src")
from utils.handwriting_quality import assess_handwriting_quality as _assess
result = _assess(image_path)
output = _json.dumps(result)
    ::py::
    return output;
}
