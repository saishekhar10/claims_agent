"""Entry point for the insurance claims processing agent.

Usage:
  jac src/main.jac <claims_folder>              — batch: process all claims in folder
  jac src/main.jac <claims_folder> <claim_id>   — single: process one claim
  Single mode auto-enters interactive chat if the claim needs a customer reply.
"""

import from dotenv { load_dotenv }
import from byllm.lib { Image }
import from src.types { ClaimResult }
import from src.tools { transcribe_image, assess_image_handwriting_quality }
import from src.agent { process_claim, prioritize_claims }
import json;


"""Load all files from a single claim folder. PDFs and text files are extracted directly.
Images are assessed for handwriting quality then transcribed via LLM vision.
Returns document_contents JSON: {filename: {file_type, text, ?handwriting_quality}}"""
def preprocess_claim_folder(claim_folder_path: str) -> str {
    output: str = "";
    image_filenames: list = [];
    image_paths: list = [];
    text_docs_json: str = "";

    # Load PDFs and text files; collect image metadata
    ::py::
    import json as _json, sys as _sys
    _sys.path.insert(0, "src")
    from utils.file_loader import load_claim_folder, read_text_file
    from utils.pdf_reader import extract_text_from_pdf

    files = load_claim_folder(claim_folder_path)
    docs = {}
    for rel_path, info in files.items():
        if not info.get("supported"):
            continue
        ext = info["ext"]
        fname = info["filename"]
        fpath = info["path"]
        if ext == ".pdf":
            try:
                docs[fname] = {"file_type": "pdf", "text": extract_text_from_pdf(fpath)}
            except Exception as e:
                docs[fname] = {"file_type": "pdf", "text": f"[ERROR: {e}]"}
        elif ext == ".txt":
            try:
                docs[fname] = {"file_type": "text", "text": read_text_file(fpath)}
            except Exception as e:
                docs[fname] = {"file_type": "text", "text": f"[ERROR: {e}]"}
        elif ext in (".png", ".jpg", ".jpeg"):
            image_filenames.append(fname)
            image_paths.append(fpath)
    text_docs_json = _json.dumps(docs)
    ::py::

    # Assess handwriting quality and transcribe each image
    image_quality_strs: list = [];
    image_text_strs: list = [];

    for img_path in image_paths {
        quality_str = assess_image_handwriting_quality(img_path);
        transcribed = transcribe_image(Image(img_path));
        image_quality_strs.append(quality_str);
        image_text_strs.append(transcribed);
    }

    # Merge image results into docs
    ::py::
    import json as _json2
    docs_final = _json2.loads(text_docs_json)
    for _i, _fname in enumerate(image_filenames):
        docs_final[_fname] = {
            "file_type": "image",
            "text": image_text_strs[_i],
            "handwriting_quality": _json2.loads(image_quality_strs[_i])
        }
    output = _json2.dumps(docs_final)
    ::py::

    return output;
}


"""Serialize a ClaimResult Jac object to a pretty-printed JSON string."""
def serialize_result(result: ClaimResult) -> str {
    output: str = "";
    ::py::
    import json as _json3

    def _ser(obj):
        if obj is None:
            return None
        if isinstance(obj, (str, int, float, bool)):
            return obj
        if isinstance(obj, list):
            return [_ser(i) for i in obj]
        if isinstance(obj, dict):
            return {k: _ser(v) for k, v in obj.items()}
        try:
            return obj.name  # Jac/Python enum
        except AttributeError:
            pass
        if hasattr(obj, '__dict__'):
            return {k: _ser(v) for k, v in vars(obj).items() if not k.startswith('_')}
        return str(obj)

    output = _json3.dumps(_ser(result), indent=2)
    ::py::
    return output;
}


"""Write claim result JSON to outputs/<claim_id>.json."""
def save_result(claim_id: str, result_json: str) -> None {
    ::py::
    import os as _os
    _os.makedirs("outputs", exist_ok=True)
    out_path = _os.path.join("outputs", f"{claim_id}.json")
    with open(out_path, "w") as _f:
        _f.write(result_json)
    print(f"  Saved → {out_path}")
    ::py::
}


"""Print a one-screen summary of a ClaimResult."""
def print_summary(claim_id: str, result: ClaimResult) -> None {
    ::py::
    sep = "=" * 60
    print(f"\n{sep}")
    print(f"  Claim : {claim_id}")
    try:
        print(f"  Status: {result.status.name}")
    except Exception:
        print(f"  Status: {result.status}")
    try:
        action_name = result.next_action.type.name
        print(f"  Action: {action_name}")
    except Exception:
        action_name = ""
    if result.issues:
        print(f"  Issues ({len(result.issues)}):")
        for iss in result.issues[:6]:
            try:
                print(f"    [{iss.type.name}] {iss.description}")
            except Exception:
                print(f"    {iss}")
    msg = ""
    try:
        msg = result.next_action.message or ""
    except Exception:
        pass
    if msg:
        print(f"\n  Customer message:\n    {msg}")
    print(sep)
    ::py::
}


"""Return a sorted list of claim IDs (subdirectory names) found in the claims folder."""
def list_claim_ids(claims_folder: str) -> list {
    ids: list = [];
    ::py::
    import os as _os2
    try:
        entries = sorted(_os2.listdir(claims_folder))
        for entry in entries:
            full = _os2.path.join(claims_folder, entry)
            if _os2.path.isdir(full) and not entry.startswith('.'):
                ids.append(entry)
    except Exception as e:
        print(f"ERROR listing {claims_folder}: {e}")
    ::py::
    return ids;
}


"""Interactive chat loop: show customer message, accept user reply, re-process claim.
Exits when the agent reaches FINALIZE or the user types quit/exit/q."""
def run_interactive_loop(claim_id: str, doc_contents_json: str, initial_result: ClaimResult) -> None {
    current_result = initial_result;
    current_docs = doc_contents_json;
    reply_count: int = 0;
    loop_active: bool = True;

    while loop_active {
        # Check whether agent wants a customer reply
        needs_reply: bool = False;
        ::py::
        try:
            at_name = current_result.next_action.type.name
            needs_reply = at_name == "MESSAGE_CUSTOMER"
        except Exception:
            needs_reply = False
        ::py::

        if not needs_reply {
            print(f"\nClaim {claim_id}: no further customer response needed. Exiting interactive mode.");
            loop_active = False;
        } else {
            user_input: str = "";
            ::py::
            try:
                user_input = input("\nEnter customer reply (or 'quit' to exit): ").strip()
            except (EOFError, KeyboardInterrupt):
                user_input = "quit"
            ::py::

            is_quit: bool = False;
            ::py::
            is_quit = user_input.lower() in ("quit", "exit", "q", "")
            ::py::

            if is_quit {
                print("\nExiting interactive mode.");
                loop_active = False;
            } else {
                reply_count += 1;
                reply_key: str = f"customer_reply_{reply_count}.txt";
                updated_docs: str = "";

                ::py::
                import json as _json4
                _docs = _json4.loads(current_docs)
                _docs[reply_key] = {"file_type": "text", "text": user_input}
                updated_docs = _json4.dumps(_docs)
                ::py::

                print(f"\nRe-processing {claim_id} with customer reply...");
                current_result = process_claim(claim_id, updated_docs);
                current_docs = updated_docs;
                print_summary(claim_id, current_result);

                is_finalized: bool = False;
                ::py::
                try:
                    is_finalized = current_result.next_action.type.name == "FINALIZE"
                except Exception:
                    is_finalized = False
                ::py::

                if is_finalized {
                    print(f"\nClaim {claim_id} is COMPLETE. Finalizing.");
                    loop_active = False;
                }

                updated_json: str = serialize_result(current_result);
                save_result(claim_id, updated_json);
            }
        }
    }
}


with entry {
    load_dotenv(".env");

    # Parse arguments
    claims_folder: str = "";
    target_claim_id: str = "";

    ::py::
    import sys as _sys2
    _argv = _sys2.argv[:]
    _positional = [a for a in _argv[1:] if not a.endswith('.jac') and not a.startswith('--')]
    if _positional:
        claims_folder = _positional[0]
    if len(_positional) >= 2:
        target_claim_id = _positional[1]
    ::py::

    if not claims_folder {
        print("Usage:");
        print("  Batch:  jac src/main.jac <claims_folder>");
        print("  Single: jac src/main.jac <claims_folder> <claim_id>");
        ::py::
        import sys; sys.exit(1)
        ::py::
    }

    if target_claim_id {
        # ── SINGLE MODE ────────────────────────────────────────────────────────
        claim_dir: str = f"{claims_folder}/{target_claim_id}";
        print(f"\nProcessing {target_claim_id} from {claim_dir} ...");

        doc_contents = preprocess_claim_folder(claim_dir);
        result = process_claim(target_claim_id, doc_contents);
        result_json_str = serialize_result(result);
        save_result(target_claim_id, result_json_str);
        print_summary(target_claim_id, result);

        # Auto-enter interactive mode if agent needs customer reply
        needs_chat: bool = False;
        ::py::
        try:
            needs_chat = result.next_action.type.name == "MESSAGE_CUSTOMER"
        except Exception:
            needs_chat = False
        ::py::

        if needs_chat {
            run_interactive_loop(target_claim_id, doc_contents, result);
        }

    } else {
        # ── BATCH MODE ─────────────────────────────────────────────────────────
        print(f"\nBatch processing all claims in {claims_folder} ...");

        claim_ids = list_claim_ids(claims_folder);

        if not claim_ids {
            print(f"No claim folders found in {claims_folder}.");
            ::py::
            import sys; sys.exit(1)
            ::py::
        }

        print(f"Found {len(claim_ids)} claim(s): {', '.join(claim_ids)}\n");

        all_result_jsons: list = [];

        for cid in claim_ids {
            claim_dir_b: str = f"{claims_folder}/{cid}";
            print(f"Processing {cid} ...");

            docs_b = preprocess_claim_folder(claim_dir_b);
            result_b = process_claim(cid, docs_b);
            result_json_b = serialize_result(result_b);
            save_result(cid, result_json_b);
            print_summary(cid, result_b);

            all_result_jsons.append(result_json_b);
        }

        # Prioritize all claims
        print("\nPrioritizing claims...");
        combined_json: str = "";
        ::py::
        import json as _json5
        _parsed_results = [_json5.loads(r) for r in all_result_jsons]
        combined_json = _json5.dumps(_parsed_results)
        ::py::

        priority_output = prioritize_claims(combined_json);
        print(f"\nProcessing order:\n{priority_output}");

        ::py::
        import os as _os3, json as _json6
        _os3.makedirs("outputs", exist_ok=True)
        with open("outputs/processing_order.json", "w") as _pf:
            try:
                _json6.dump(_json6.loads(priority_output), _pf, indent=2)
            except Exception:
                _pf.write(priority_output)
        print("\nSaved → outputs/processing_order.json")
        ::py::
    }
}
