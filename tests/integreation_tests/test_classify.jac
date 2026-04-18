import from dotenv { load_dotenv }
import from src.tools { classify_document }
import from src.types { DocType }

with entry {
    load_dotenv(".env");
    text = "ANN ARBOR POLICE DEPARTMENT\nTraffic Accident / Incident Report\nReport No: AA-2026-00437\nOfficer: J. Martinez Badge #4821\nDATE OF INCIDENT: 02/14/2026\nVEHICLE: 2020 Honda Accord";
    result = classify_document(text);
    print(f"classify_document result: {result}");
    assert result == DocType.POLICE_REPORT, f"Expected POLICE_REPORT, got {result}";
    print("PASS: classify_document correctly identified POLICE_REPORT");
}
