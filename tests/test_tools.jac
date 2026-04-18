"""Unit tests for deterministic tools in src/tools.jac."""

import from src.tools { validate_vin, reconcile_field, detect_duplicates }
import json;

# ── validate_vin ──────────────────────────────────────────────────────────────

test "vin: valid 17-char alphanumeric passes" {
    assert validate_vin("1HGCM82633A004352") == "VALID";
}

test "vin: all digits and letters (no I/O/Q) passes" {
    assert validate_vin("2T1BURHE5JC034127") == "VALID";
}

test "vin: strips whitespace before validating" {
    assert validate_vin("  1HGCM82633A004352  ") == "VALID";
}

test "vin: too short returns INVALID with char count" {
    result = validate_vin("1HGCM826");
    assert "INVALID" in result;
    assert "17" in result;
}

test "vin: too long returns INVALID" {
    result = validate_vin("1HGCM82633A004352XX");
    assert "INVALID" in result;
    assert "17" in result;
}

test "vin: contains I returns INVALID mentioning I" {
    result = validate_vin("1HGCM82633I004352");
    assert "INVALID" in result;
    assert "I" in result;
}

test "vin: contains O returns INVALID mentioning O" {
    result = validate_vin("1HGCM82633O004352");
    assert "INVALID" in result;
    assert "O" in result;
}

test "vin: contains Q returns INVALID mentioning Q" {
    result = validate_vin("1HGCM82633Q004352");
    assert "INVALID" in result;
    assert "Q" in result;
}

test "vin: empty string returns INVALID" {
    result = validate_vin("");
    assert "INVALID" in result;
}

test "vin: special characters returns INVALID" {
    result = validate_vin("1HGCM826-3A00435");
    assert "INVALID" in result;
}

# ── reconcile_field ───────────────────────────────────────────────────────────

test "reconcile: single entry returned as-is" {
    data = json.dumps([{"value": "1HGCM82633A004352", "confidence": "HIGH", "source": "police_report.pdf"}]);
    result = json.loads(reconcile_field(data));
    assert result["recommended_value"] == "1HGCM82633A004352";
    assert result["has_conflict"] == False;
    assert result["chosen_source"] == "police_report.pdf";
}

test "reconcile: two matching values — no conflict" {
    data = json.dumps([
        {"value": "$18,500", "confidence": "HIGH", "source": "settlement_breakdown.pdf"},
        {"value": "$18,500", "confidence": "MEDIUM", "source": "police_report.pdf"}
    ]);
    result = json.loads(reconcile_field(data));
    assert result["has_conflict"] == False;
    assert result["recommended_value"] == "$18,500";
}

test "reconcile: HIGH beats LOW when values match" {
    data = json.dumps([
        {"value": "$18,500", "confidence": "LOW", "source": "adjuster_note.png"},
        {"value": "$18,500", "confidence": "HIGH", "source": "settlement_breakdown.pdf"}
    ]);
    result = json.loads(reconcile_field(data));
    assert result["confidence"] == "HIGH";
    assert result["chosen_source"] == "settlement_breakdown.pdf";
}

test "reconcile: conflicting values flagged" {
    data = json.dumps([
        {"value": "1HGCM82633A004352", "confidence": "HIGH", "source": "police_report.pdf"},
        {"value": "1HGCM82633A004353", "confidence": "MEDIUM", "source": "finance_agreement.pdf"}
    ]);
    result = json.loads(reconcile_field(data));
    assert result["has_conflict"] == True;
    assert len(result["conflicts"]) > 0;
    assert result["recommended_value"] == "1HGCM82633A004352";
}

test "reconcile: police_report wins tie over finance_agreement" {
    data = json.dumps([
        {"value": "02/14/2026", "confidence": "HIGH", "source": "finance_agreement.pdf"},
        {"value": "02/14/2026", "confidence": "HIGH", "source": "police_report.pdf"}
    ]);
    result = json.loads(reconcile_field(data));
    assert result["chosen_source"] == "police_report.pdf";
}

test "reconcile: empty input returns error" {
    data = json.dumps([]);
    result = json.loads(reconcile_field(data));
    assert "error" in result;
}

# ── detect_duplicates ─────────────────────────────────────────────────────────

test "duplicates: identical texts flagged" {
    text = "ANN ARBOR POLICE DEPARTMENT\nReport No: AA-2026-00437\nVIN: 1HGCM82633A004352";
    data = json.dumps({"police_report.pdf": text, "police_report_copy.pdf": text});
    result = json.loads(detect_duplicates(data));
    assert len(result["pairs"]) == 1;
    assert result["pairs"][0]["is_duplicate"] == True;
    assert result["pairs"][0]["similarity_pct"] == 100.0;
}

test "duplicates: completely different texts not flagged" {
    data = json.dumps({
        "police_report.pdf": "POLICE DEPARTMENT incident report officer badge number",
        "finance_agreement.pdf": "LOAN AGREEMENT lender borrower monthly payment interest rate"
    });
    result = json.loads(detect_duplicates(data));
    assert result["pairs"][0]["is_duplicate"] == False;
}

test "duplicates: revision marker noted in notes" {
    text = "Settlement Breakdown\nActual Cash Value: $18,500\nDeductible: $500\nNet Payment: $18,000";
    data = json.dumps({
        "settlement_breakdown.pdf": text,
        "settlement_breakdown_v2.pdf": text
    });
    result = json.loads(detect_duplicates(data));
    assert result["pairs"][0]["is_duplicate"] == True;
    assert "revision" in result["pairs"][0]["notes"].lower();
}

test "duplicates: single file returns no pairs" {
    data = json.dumps({"police_report.pdf": "some text"});
    result = json.loads(detect_duplicates(data));
    assert len(result["pairs"]) == 0;
}

test "duplicates: three files produces three pairs" {
    data = json.dumps({
        "a.pdf": "alpha bravo charlie delta",
        "b.pdf": "echo foxtrot golf hotel",
        "c.pdf": "india juliet kilo lima"
    });
    result = json.loads(detect_duplicates(data));
    assert len(result["pairs"]) == 3;
}
