import from dotenv { load_dotenv }
import from src.tools { extract_fields }
import from src.types { DocType, Confidence }

with entry {
    load_dotenv(".env");
    text = "ANN ARBOR POLICE DEPARTMENT\nVEHICLE INFORMATION\nVIN: 2T1BURHE5JC034127\nDATE OF INCIDENT: 03/15/2026\n2019 Toyota Corolla\nDamage: Total Loss";
    result = extract_fields(DocType.POLICE_REPORT, text);
    print(f"VIN: {result.vin}");
    print(f"Date of Loss: {result.date_of_loss}");
    assert result.vin is not None and result.vin.value != "", "VIN should be extracted";
    assert "2T1BURHE5JC034127" in result.vin.value, f"VIN value mismatch: {result.vin.value}";
    assert result.vin.confidence == Confidence.HIGH, f"Expected HIGH confidence, got {result.vin.confidence}";
    assert result.date_of_loss is not None, "Date of loss should be extracted";
    assert "03/15/2026" in result.date_of_loss.value, f"Date mismatch: {result.date_of_loss.value}";
    print("PASS: extract_fields returned correct values with HIGH confidence");
}
