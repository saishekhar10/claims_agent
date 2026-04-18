"""Type definitions for the insurance claims processing agent."""

# ── Enumerations ──────────────────────────────────────────────────────────────

enum Confidence { HIGH, MEDIUM, LOW }

sem Confidence.HIGH = "Labeled field in a clean machine-readable PDF, OR value confirmed identically across multiple documents. No ambiguity in source or extraction.";
sem Confidence.MEDIUM = "Extracted from a scanned image via OCR, or inferred from narrative/prose text (e.g. 'the vehicle worth $18,000'). Some uncertainty in accuracy.";
sem Confidence.LOW = "Handwritten document, heavily degraded scan, approximate language (e.g. 'around $X', 'roughly'), or value appears only in self-reported customer correspondence. Requires human verification.";

enum DocType {
    POLICE_REPORT,
    FINANCE_AGREEMENT,
    SETTLEMENT_BREAKDOWN,
    ADJUSTER_NOTE,
    TOW_RECEIPT,
    CUSTOMER_EMAIL,
    UNKNOWN
}

sem DocType.POLICE_REPORT = "Official law enforcement accident or incident report — authoritative source for date of loss, location, and vehicle information including VIN.";
sem DocType.FINANCE_AGREEMENT = "Loan or vehicle financing contract — authoritative source for outstanding loan balance owed on the vehicle.";
sem DocType.SETTLEMENT_BREAKDOWN = "Insurance payout calculation document — itemizes total loss value, deductions, and net settlement amount paid to the claimant.";
sem DocType.ADJUSTER_NOTE = "Field notes or damage assessment written by an insurance adjuster — often handwritten, lower reliability, treated as supplemental.";
sem DocType.TOW_RECEIPT = "Receipt from a towing or vehicle recovery service — supplemental document, not required for claim completeness.";
sem DocType.CUSTOMER_EMAIL = "Email or written correspondence from the policyholder — may provide missing info in response to a prior request, treat as self-reported.";
sem DocType.UNKNOWN = "Document type could not be identified from its content.";

enum ClaimStatus { COMPLETE, INCOMPLETE, NEEDS_REVIEW }

sem ClaimStatus.COMPLETE = "All three required documents present (police report, finance agreement, settlement breakdown), all four key fields extracted at MEDIUM or HIGH confidence, and no cross-document conflicts detected.";
sem ClaimStatus.INCOMPLETE = "One or more required documents are absent, or one or more required fields (VIN, date of loss, insurance payout, loan balance) could not be extracted from available documents.";
sem ClaimStatus.NEEDS_REVIEW = "Conflicting field values across documents, one or more LOW-confidence extractions that cannot be resolved automatically, duplicate documents with differing content, or other ambiguity requiring human judgment.";

enum ActionType { FINALIZE, MESSAGE_CUSTOMER, ESCALATE }

sem ActionType.FINALIZE = "Claim is complete and validated — all documents present, fields extracted, no conflicts. Ready to process payout.";
sem ActionType.MESSAGE_CUSTOMER = "Contact the customer to request missing documents or to ask them to resolve inconsistencies.";
sem ActionType.ESCALATE = "Forward to a human reviewer — unresolvable conflicts, multiple LOW-confidence extractions, or edge cases beyond automated handling.";

enum IssueType { INCONSISTENCY, MISSING, INVALID, LOW_CONFIDENCE }

sem IssueType.INCONSISTENCY = "The same field has conflicting values in two or more documents (e.g. VIN differs between police report and finance agreement).";
sem IssueType.MISSING = "A required document type or required field is absent from the claim.";
sem IssueType.INVALID = "A field value fails a validation rule — e.g. VIN is not exactly 17 alphanumeric characters, or date cannot be parsed.";
sem IssueType.LOW_CONFIDENCE = "A field was extracted but with LOW confidence and the value may be incorrect or approximate.";

# ── Objects ───────────────────────────────────────────────────────────────────

obj FieldResult {
    has value: str = "";
    has confidence: Confidence = Confidence.LOW;
    has source: str = "";
    has reason: str = "";
}

sem FieldResult.value = "The extracted field value as a string (e.g. '1HGCM82633A004352', '02/14/2026', '$18,500'). Empty string if the field was not found in this document.";
sem FieldResult.confidence = "Reliability of this extraction — HIGH for labeled PDF fields, MEDIUM for OCR/narrative, LOW for handwritten or approximate.";
sem FieldResult.source = "Filename of the document this value was extracted from (e.g. 'police_report.pdf'). Empty string if not applicable.";
sem FieldResult.reason = "Required when confidence is MEDIUM or LOW — brief explanation of why confidence is reduced. Empty string when confidence is HIGH.";

obj ExtractedFields {
    has vin: FieldResult | None = None;
    has date_of_loss: FieldResult | None = None;
    has insurance_payout: FieldResult | None = None;
    has loan_balance: FieldResult | None = None;
    has additional_facts: dict[str, FieldResult] = {};
}

sem ExtractedFields.additional_facts = "Open-ended fact storage for any relevant claim information discovered during processing. Keys are fact names (e.g., 'car_make', 'incident_location', 'weather'), values are FieldResult objects with confidence and source tracking. Allows the agent to capture variable information across different claim types without schema changes.";
sem ExtractedFields.vin = "Vehicle Identification Number — must be exactly 17 alphanumeric characters. Flag INVALID if length or format is wrong.";
sem ExtractedFields.date_of_loss = "Date the vehicle loss occurred — must be a valid calendar date. Cross-check between police report and other documents.";
sem ExtractedFields.insurance_payout = "Total insurance settlement payout amount — must be numeric. Found in settlement breakdown document.";
sem ExtractedFields.loan_balance = "Outstanding loan balance on the vehicle at time of loss — must be numeric. Found in finance agreement.";

obj DocumentInfo {
    has filename: str = "";
    has doc_type: DocType = DocType.UNKNOWN;
    has is_duplicate: bool = False;
    has duplicate_of: str | None = None;
}

sem DocumentInfo.filename = "Name of the file as it appears in the claim folder (e.g. 'police_report.pdf').";
sem DocumentInfo.doc_type = "Identified document type based on content analysis.";
sem DocumentInfo.is_duplicate = "True if this document's content is substantially identical to another document in the same claim.";
sem DocumentInfo.duplicate_of = "Filename of the original document this is a duplicate of (e.g. 'settlement_breakdown.pdf'). Null if not a duplicate.";

obj DocumentsSummary {
    has identified: list[DocumentInfo] = [];
    has missing: list[str] = [];
    has duplicates: list[str] = [];
}

sem DocumentsSummary.identified = "All documents found in the claim folder with their identified types — include every file, even unknown types.";
sem DocumentsSummary.missing = "Required document types not present in the claim. Subset of: ['police_report', 'finance_agreement', 'settlement_breakdown'].";
sem DocumentsSummary.duplicates = "Filenames of documents identified as duplicates of another document in the same claim.";

obj Issue {
    has type: IssueType = IssueType.MISSING;
    has description: str = "";
    has details: str | None = None;
}

sem Issue.type = "Category of the problem flagged.";
sem Issue.description = "Short human-readable summary of the issue (e.g. 'VIN mismatch between police report and finance agreement').";
sem Issue.details = "Additional detail — for INCONSISTENCY, list which documents disagree and show both values. For MISSING, name the missing item.";

obj NextAction {
    has type: ActionType = ActionType.ESCALATE;
    has message: str | None = None;
}

sem NextAction.type = "The recommended next step for this claim.";
sem NextAction.message = "Customer-facing message text when type is MESSAGE_CUSTOMER — polite, specific, asks for exactly what is missing. Null for FINALIZE or ESCALATE.";

obj ToolUsage {
    has tool: str = "";
    has input: str = "";
    has result: str = "";
}

sem ToolUsage.tool = "Name of the tool that was called (e.g. 'extract_text_from_pdf').";
sem ToolUsage.input = "Input passed to the tool (e.g. the file path).";
sem ToolUsage.result = "Short summary of what the tool returned or accomplished.";

obj ClaimResult {
    has claim_id: str = "";
    has status: ClaimStatus = ClaimStatus.INCOMPLETE;
    has extracted_fields: ExtractedFields | None = None;
    has documents: DocumentsSummary | None = None;
    has issues: list[Issue] = [];
    has next_action: NextAction | None = None;
    has tools_used: list[ToolUsage] = [];
}

sem ClaimResult.claim_id = "Claim identifier, e.g. 'CLM-001'.";
sem ClaimResult.status = "Overall completeness and validity assessment of this claim.";
sem ClaimResult.extracted_fields = "The four key fields extracted from documents — always populate even if some are None.";
sem ClaimResult.documents = "Summary of all documents: identified types, missing required docs, and detected duplicates.";
sem ClaimResult.issues = "All flagged problems — include every inconsistency, missing item, validation failure, and low-confidence extraction.";
sem ClaimResult.next_action = "Recommended action and optional customer message.";
sem ClaimResult.tools_used = "Log of every tool called during processing of this claim.";
