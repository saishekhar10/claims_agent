import from dotenv { load_dotenv }
import from src.tools { transcribe_image }
import from byllm.lib { Image }

with entry {
    load_dotenv(".env");
    img = Image("claims/CLM-001/adjuster_note.png");
    result = transcribe_image(img);
    print(f"Transcription ({len(result)} chars):");
    print(result);
    assert len(result) > 50, f"Expected substantial transcription, got {len(result)} chars";
    print("PASS: transcribe_image returned readable text from PNG");
}
