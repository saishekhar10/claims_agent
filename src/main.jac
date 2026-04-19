"""Entry point for the insurance claims processing agent.

Usage:
  jac src/main.jac <claims_folder>                  — batch: display all processed claims
  jac src/main.jac <claims_folder> <claim_id>       — single: display one claim + interactive menu
  jac src/main.jac <claims_folder> prioritize       — re-run prioritization on existing outputs
  On first run (no output file yet), the agent processes the claim automatically.
  After that, the agent only runs when the user provides new input through the menu.
"""

import from dotenv { load_dotenv }
import from byllm.lib { Image }
import from src.types { ClaimResult }
import from src.tools { transcribe_image, assess_image_handwriting_quality }
import from src.agent { process_claim, prioritize_claims }
import json;


"""Load all files from a single claim folder. PDFs and text files are extracted directly.
Images are assessed for handwriting quality then transcribed via LLM vision.
Results are cached to outputs/.cache/{claim_id}/ — cache is checked before any LLM call.
Returns document_contents JSON: {filename: {file_type, text, ?handwriting_quality}}"""
def preprocess_claim_folder(claim_folder_path: str, claim_id: str) -> str {
    output: str = "";
    image_filenames: list = [];
    image_paths: list = [];
    text_docs_json: str = "";

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

    image_quality_strs: list = [];
    image_text_strs: list = [];

    for img_path in image_paths {
        # ── quality cache ─────────────────────────────────────────────────────
        quality_str: str = "";
        cache_hit_quality: bool = False;
        ::py::
        import os as _osc, json as _jc
        _fname_q = _osc.path.basename(img_path)
        _cache_dir = _osc.path.join("outputs", ".cache", claim_id)
        _osc.makedirs(_cache_dir, exist_ok=True)
        _quality_cache = _osc.path.join(_cache_dir, _fname_q + ".quality.json")
        if _osc.path.isfile(_quality_cache):
            with open(_quality_cache) as _qf:
                quality_str = _qf.read()
            cache_hit_quality = True
        ::py::
        if not cache_hit_quality {
            quality_str = assess_image_handwriting_quality(img_path);
            ::py::
            with open(_quality_cache, "w") as _qfw:
                _qfw.write(quality_str)
            ::py::
        }

        # ── transcription cache ───────────────────────────────────────────────
        transcribed: str = "";
        cache_hit_text: bool = False;
        ::py::
        _fname_t = _osc.path.basename(img_path)
        _text_cache = _osc.path.join(_cache_dir, _fname_t + ".txt")
        if _osc.path.isfile(_text_cache):
            with open(_text_cache) as _tf:
                transcribed = _tf.read()
            cache_hit_text = True
        ::py::
        if not cache_hit_text {
            transcribed = transcribe_image(Image(img_path));
            ::py::
            with open(_text_cache, "w") as _tfw:
                _tfw.write(transcribed)
            ::py::
        }

        image_quality_strs.append(quality_str);
        image_text_strs.append(transcribed);
    }

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
            return obj.name
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
    ::py::
}


"""Read outputs/<claim_id>.json and return it, or empty string if not found."""
def load_output(claim_id: str) -> str {
    result_json: str = "";
    found: bool = False;
    ::py::
    import os as _os_lo
    _path = _os_lo.path.join("outputs", f"{claim_id}.json")
    if _os_lo.path.isfile(_path):
        with open(_path) as _f:
            result_json = _f.read()
        found = True
    ::py::
    if found {
        return result_json;
    }
    return "";
}


"""Write document_contents JSON to outputs/<claim_id>.docs.json."""
def save_docs(claim_id: str, docs_json: str) -> None {
    ::py::
    import os as _os_sd
    _os_sd.makedirs("outputs", exist_ok=True)
    with open(_os_sd.path.join("outputs", f"{claim_id}.docs.json"), "w") as _f:
        _f.write(docs_json)
    ::py::
}


"""Read outputs/<claim_id>.docs.json, or empty string if not found."""
def load_docs(claim_id: str) -> str {
    docs_json: str = "";
    ::py::
    import os as _os_ld
    _path = _os_ld.path.join("outputs", f"{claim_id}.docs.json")
    if _os_ld.path.isfile(_path):
        with open(_path) as _f:
            docs_json = _f.read()
    ::py::
    return docs_json;
}


"""Render a rich panel for a claim result dict (already deserialized to plain dict)."""
def display_result_dict(claim_id: str, result_dict_json: str) -> None {
    ::py::
    import json as _json_d
    from rich.console import Console as _Con
    from rich.panel import Panel as _Panel
    from rich.table import Table as _Table
    from rich.text import Text as _Text
    from rich.console import Group as _Group

    _console = _Con()
    r = _json_d.loads(result_dict_json)

    _status_colors = {"COMPLETE": "bold green", "INCOMPLETE": "bold yellow", "NEEDS_REVIEW": "bold red"}
    _action_colors = {"FINALIZE": "bold blue", "MESSAGE_CUSTOMER": "bold orange3", "ESCALATE": "bold red"}

    status_str = r.get("status", "UNKNOWN")
    action_str = (r.get("next_action") or {}).get("type", "")

    header = _Text()
    header.append(f"Claim {claim_id}", style="bold white")
    header.append("  ")
    header.append(f" {status_str} ", style=f"{_status_colors.get(status_str, 'white')} on grey23")
    if action_str:
        header.append("  ")
        header.append(f" {action_str} ", style=f"{_action_colors.get(action_str, 'white')} on grey23")

    _conf_fmt = {"HIGH": "[green]HIGH ✓[/green]", "MEDIUM": "[yellow]MED ~[/yellow]", "LOW": "[red]LOW ✗[/red]"}
    ef = r.get("extracted_fields") or {}

    field_table = _Table(show_header=True, header_style="bold dim", box=None, padding=(0, 1))
    field_table.add_column("Field", style="dim", min_width=18)
    field_table.add_column("Value", min_width=22)
    field_table.add_column("Conf", min_width=8)
    field_table.add_column("Source", style="dim", min_width=20)

    for fname, label in [("vin","VIN"),("date_of_loss","Date of Loss"),
                          ("insurance_payout","Ins. Payout"),("loan_balance","Loan Balance")]:
        fval = ef.get(fname)
        if fval and fval.get("value"):
            conf_key = (fval.get("confidence") or "LOW").upper()
            field_table.add_row(label, fval["value"], _conf_fmt.get(conf_key, "?"), fval.get("source",""))
        else:
            field_table.add_row(label, "[dim]—[/dim]", "[dim]—[/dim]", "[dim]—[/dim]")

    docs = r.get("documents") or {}
    identified = [d["filename"] for d in (docs.get("identified") or [])]
    missing = docs.get("missing") or []
    duplicates = docs.get("duplicates") or []

    doc_line = _Text()
    doc_line.append("Documents  ", style="bold dim")
    doc_line.append("Found: ", style="dim")
    doc_line.append(", ".join(identified) if identified else "none")
    if duplicates:
        doc_line.append("  Dupes: ", style="dim")
        doc_line.append(", ".join(duplicates), style="yellow")
    if missing:
        doc_line.append("  Missing: ", style="dim")
        doc_line.append(", ".join(missing), style="bold red")

    _issue_colors = {
        "INCONSISTENCY": "bold magenta", "MISSING": "bold yellow",
        "INVALID": "bold red", "LOW_CONFIDENCE": "bold orange3",
    }
    issues = r.get("issues") or []

    content_parts = [field_table, "", doc_line]
    if issues:
        content_parts.append("")
        content_parts.append(_Text("Issues", style="bold dim"))
        for iss in issues:
            itype = (iss.get("type") or "").upper()
            issue_line = _Text()
            issue_line.append(f" {itype} ", style=f"{_issue_colors.get(itype, 'white')} on grey23")
            issue_line.append(f"  {iss.get('description','')}")
            content_parts.append(issue_line)

    _console.print(_Panel(_Group(*content_parts), title=header, border_style="bright_black", padding=(1, 2)))

    msg = (r.get("next_action") or {}).get("message")
    if msg:
        _console.print(_Panel(msg, title="[bold cyan]Agent Message[/bold cyan]",
                              border_style="cyan", padding=(1, 2)))
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


"""Read all outputs/<id>.json files, call prioritize_claims, save and display ranked table.
Always re-runs the LLM prioritization — ignores any existing processing_order.json."""
def run_prioritize(claims_folder: str) -> None {
    claim_ids = list_claim_ids(claims_folder);
    all_result_jsons: list = [];
    missing_outputs: list = [];

    for cid in claim_ids {
        rj: str = load_output(cid);
        if rj {
            all_result_jsons.append(rj);
        } else {
            missing_outputs.append(cid);
        }
    }

    if missing_outputs {
        ::py::
        from rich.console import Console as _cpm
        _cpm().print(f"[yellow]No output yet for: {', '.join(missing_outputs)} — skipping.[/yellow]")
        ::py::
    }

    if not all_result_jsons {
        ::py::
        from rich.console import Console as _cpnone
        _cpnone().print("[red]No processed claims found in outputs/. Run single mode first.[/red]")
        import sys; sys.exit(1)
        ::py::
    }

    ::py::
    from rich.console import Console as _cpstart
    _cpstart().print(f"\n[bold]Prioritizing {len(all_result_jsons)} claim(s)…[/bold]")
    ::py::

    combined_json: str = "";
    ::py::
    import json as _jcp
    combined_json = _jcp.dumps([_jcp.loads(r) for r in all_result_jsons])
    ::py::

    priority_output = prioritize_claims(combined_json);

    ::py::
    import os as _oscp, json as _jcp2
    _po_stripped = priority_output.strip()
    if _po_stripped.startswith("```"):
        _po_stripped = _po_stripped.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    _oscp.makedirs("outputs", exist_ok=True)
    with open("outputs/processing_order.json", "w") as _pof:
        try:
            _jcp2.dump(_jcp2.loads(_po_stripped), _pof, indent=2)
        except Exception:
            _pof.write(priority_output)
    priority_json = _po_stripped
    ::py::

    # Render ranked table
    ::py::
    import json as _jrt
    from rich.console import Console as _crt2
    from rich.table import Table as _Tbl2
    from rich.text import Text as _Txt2

    _status_colors_p = {"COMPLETE": "bold green", "INCOMPLETE": "bold yellow", "NEEDS_REVIEW": "bold red"}
    _results_by_id_p = {}
    for _rj in all_result_jsons:
        _rd = _jrt.loads(_rj)
        _results_by_id_p[_rd.get("claim_id", "")] = _rd

    try:
        _pdata = _jrt.loads(priority_json)
        _order = _pdata.get("processing_order", [])

        _tbl = _Tbl2(title="[bold]Processing Priority[/bold]", show_header=True,
                     header_style="bold dim", show_lines=False)
        _tbl.add_column("Rank", style="bold", width=5)
        _tbl.add_column("Claim", width=10)
        _tbl.add_column("Status", width=16)
        _tbl.add_column("Reason", min_width=40)

        for _rank, _entry in enumerate(_order, 1):
            _cid = _entry.get("claim_id", "—")
            _reason = _entry.get("reason", "—")
            _rd = _results_by_id_p.get(_cid, {})
            _st = _rd.get("status", "—")
            _sc = _status_colors_p.get(_st, "white")
            _st_cell = _Txt2(f" {_st} ", style=f"{_sc} on grey23")
            _tbl.add_row(str(_rank), _cid, _st_cell, _reason)

        _con_p = _crt2()
        _con_p.print("")
        _con_p.print(_tbl)
        _con_p.print("\n[dim]Saved → outputs/processing_order.json[/dim]")
    except Exception:
        from rich.console import Console as _cfb2
        _cfb2().print(priority_json)
    ::py::
}


"""Run the agent on updated doc_contents, save results, display, return new result_json."""
def run_agent(claim_id: str, doc_contents_json: str) -> str {
    ::py::
    from rich.console import Console as _rac
    with _rac().status(f"Agent is processing {claim_id}...", spinner="dots"):
        pass
    ::py::
    result: ClaimResult = process_claim(claim_id, doc_contents_json);
    result_json: str = serialize_result(result);
    save_result(claim_id, result_json);
    save_docs(claim_id, doc_contents_json);
    display_result_dict(claim_id, result_json);
    return result_json;
}


"""Interactive menu loop. Displays existing result, waits for user input.
Agent only re-runs when user explicitly provides new documents."""
def run_interactive_loop(claim_id: str, result_json: str) -> None {
    current_result_json: str = result_json;
    loop_active: bool = True;
    turn: int = 0;
    # Load document contents from outputs/<claim_id>.docs.json (written on first run)
    doc_contents_json: str = load_docs(claim_id);

    while loop_active {
        needs_reply: bool = False;
        ::py::
        import json as _jr
        _ra = _jr.loads(current_result_json).get("next_action") or {}
        needs_reply = _ra.get("type") == "MESSAGE_CUSTOMER"
        ::py::

        if not needs_reply {
            ::py::
            from rich.console import Console as _c0
            _c0().print("[dim]No further customer response needed.[/dim]")
            ::py::
            loop_active = False;
        } else {
            turn += 1;

            # Show turn header
            ::py::
            from rich.console import Console as _c1
            _c1().print(f"\n[bold dim]── Turn {turn} ──────────────────────────────────────[/bold dim]")
            _c1().print("\n[bold]What would you like to do?[/bold]")
            _c1().print("  [cyan][1][/cyan] Paste document text")
            _c1().print("  [cyan][2][/cyan] Provide a file path  (.pdf / .png / .jpg / .jpeg / .txt)")
            _c1().print("  [cyan][3][/cyan] Provide a folder path")
            _c1().print("  [cyan][4][/cyan] Escalate to human reviewer")
            _c1().print("  [cyan][5][/cyan] Exit")
            ::py::

            choice: str = "";
            ::py::
            try:
                choice = input("\nChoice [1-5]: ").strip()
            except (EOFError, KeyboardInterrupt):
                choice = "5"
            ::py::

            if choice == "1" {
                pasted_text: str = "";
                char_count: int = 0;
                ::py::
                from rich.console import Console as _c2
                _c2().print("[dim]Paste text. Press Enter twice when done.[/dim]")
                _lines = []
                _blank_streak = 0
                while True:
                    try:
                        _ln = input()
                    except (EOFError, KeyboardInterrupt):
                        break
                    if _ln == "":
                        _blank_streak += 1
                        if _blank_streak >= 2:
                            break
                        _lines.append(_ln)
                    else:
                        _blank_streak = 0
                        _lines.append(_ln)
                pasted_text = "\n".join(_lines).strip()
                char_count = len(pasted_text)
                ::py::

                if pasted_text {
                    ::py::
                    import json as _jj1
                    _d1 = _jj1.loads(doc_contents_json)
                    _reply_count = sum(1 for k in _d1 if k.startswith("customer_reply_")) + 1
                    reply_key = f"customer_reply_{_reply_count}.txt"
                    _d1[reply_key] = {"file_type": "text", "text": pasted_text}
                    doc_contents_json = _jj1.dumps(_d1)
                    from rich.console import Console as _c3
                    _c3().print(f"[dim white]  ↳ Added {reply_key} ({char_count} chars)[/dim white]")
                    ::py::
                    current_result_json = run_agent(claim_id, doc_contents_json);
                } else {
                    ::py::
                    from rich.console import Console as _c5
                    _c5().print("[red]No text entered.[/red]")
                    ::py::
                }

            } elif choice == "2" {
                file_path_in: str = "";
                ::py::
                try:
                    file_path_in = input("File path: ").strip()
                except (EOFError, KeyboardInterrupt):
                    file_path_in = ""
                ::py::

                file_valid: bool = False;
                file_text: str = "";
                file_key: str = "";
                file_is_image: bool = False;

                ::py::
                import os as _osf, sys as _sysf
                _sysf.path.insert(0, "src")
                from rich.console import Console as _cf
                _conff = _cf()
                _VALID_EXTS = {".pdf", ".png", ".jpg", ".jpeg", ".txt"}
                if not file_path_in:
                    _conff.print("[red]No path entered.[/red]")
                elif not _osf.path.isfile(file_path_in):
                    _conff.print(f"[red]File not found: {file_path_in}[/red]")
                else:
                    _ext = _osf.path.splitext(file_path_in)[1].lower()
                    if _ext not in _VALID_EXTS:
                        _conff.print(f"[red]Unsupported extension '{_ext}'. Allowed: {', '.join(_VALID_EXTS)}[/red]")
                    else:
                        file_key = _osf.path.basename(file_path_in)
                        if _ext == ".txt":
                            from utils.file_loader import read_text_file as _rtf
                            file_text = _rtf(file_path_in)
                            file_valid = True
                        elif _ext == ".pdf":
                            from utils.pdf_reader import extract_text_from_pdf as _epdf
                            file_text = _epdf(file_path_in)
                            file_valid = True
                        else:
                            file_is_image = True
                            file_valid = True
                ::py::

                if file_valid and not file_is_image {
                    ::py::
                    import json as _jj2
                    _d2 = _jj2.loads(doc_contents_json)
                    _d2[file_key] = {"file_type": "pdf" if file_key.endswith(".pdf") else "text", "text": file_text}
                    doc_contents_json = _jj2.dumps(_d2)
                    from rich.console import Console as _c6
                    _c6().print(f"[dim white]  ↳ Loaded {file_key} ({len(file_text)} chars)[/dim white]")
                    ::py::
                    current_result_json = run_agent(claim_id, doc_contents_json);
                } elif file_valid and file_is_image {
                    file_quality_str: str = assess_image_handwriting_quality(file_path_in);
                    file_img_text: str = transcribe_image(Image(file_path_in));
                    ::py::
                    import json as _jj3
                    _d3 = _jj3.loads(doc_contents_json)
                    _d3[file_key] = {"file_type": "image", "text": file_img_text,
                                     "handwriting_quality": _jj3.loads(file_quality_str)}
                    doc_contents_json = _jj3.dumps(_d3)
                    from rich.console import Console as _c8
                    _c8().print(f"[dim white]  ↳ Transcribed {file_key}[/dim white]")
                    ::py::
                    current_result_json = run_agent(claim_id, doc_contents_json);
                }

            } elif choice == "3" {
                folder_path_in: str = "";
                ::py::
                try:
                    folder_path_in = input("Folder path: ").strip()
                except (EOFError, KeyboardInterrupt):
                    folder_path_in = ""
                ::py::

                folder_valid: bool = False;
                ::py::
                import os as _osdir
                from rich.console import Console as _cdir
                _cdircon = _cdir()
                if not folder_path_in:
                    _cdircon.print("[red]No path entered.[/red]")
                elif not _osdir.path.isdir(folder_path_in):
                    _cdircon.print(f"[red]Folder not found: {folder_path_in}[/red]")
                else:
                    folder_valid = True
                ::py::

                if folder_valid {
                    new_docs_str: str = preprocess_claim_folder(folder_path_in, claim_id);
                    ::py::
                    import json as _jj4
                    _d4 = _jj4.loads(doc_contents_json)
                    _new4 = _jj4.loads(new_docs_str)
                    _d4.update(_new4)
                    doc_contents_json = _jj4.dumps(_d4)
                    from rich.console import Console as _c10
                    _c10().print(f"[dim white]  ↳ Merged {len(_new4)} file(s) from folder[/dim white]")
                    ::py::
                    current_result_json = run_agent(claim_id, doc_contents_json);
                }

            } elif choice == "4" {
                ::py::
                from rich.console import Console as _c12
                from rich.panel import Panel as _p2
                _c12().print(_p2(
                    f"[bold]Claim {claim_id}[/bold] flagged for human review.",
                    title="[bold red]Escalated[/bold red]", border_style="red"
                ))
                ::py::
                loop_active = False;

            } elif choice == "5" {
                ::py::
                from rich.console import Console as _c13
                _c13().print(f"[dim]Exiting. Claim {claim_id} saved to outputs/.[/dim]")
                ::py::
                loop_active = False;

            } else {
                ::py::
                from rich.console import Console as _c14
                _c14().print("[red]Invalid choice. Enter 1–5.[/red]")
                ::py::
            }

            # Check if agent finalized
            is_finalized: bool = False;
            ::py::
            import json as _jfin
            try:
                is_finalized = (_jfin.loads(current_result_json).get("next_action") or {}).get("type") == "FINALIZE"
            except Exception:
                is_finalized = False
            ::py::

            if is_finalized and loop_active {
                ::py::
                from rich.console import Console as _c15
                from rich.panel import Panel as _p3
                _c15().print(_p3(
                    f"[bold green]Claim {claim_id} is COMPLETE.[/bold green] Ready to finalize payout.",
                    title="[bold green]Finalized[/bold green]", border_style="green"
                ))
                ::py::
                loop_active = False;
            }
        }
    }
}


with entry {
    load_dotenv(".env");

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
        ::py::
        from rich.console import Console as _cu
        _cu().print("[bold red]Usage:[/bold red]")
        _cu().print("  Batch:     jac src/main.jac [bold]<claims_folder>[/bold]")
        _cu().print("  Single:    jac src/main.jac [bold]<claims_folder> <claim_id>[/bold]")
        _cu().print("  Prioritize: jac src/main.jac [bold]<claims_folder> prioritize[/bold]")
        import sys; sys.exit(1)
        ::py::
    }

    if target_claim_id == "prioritize" {
        # ── PRIORITIZE MODE ────────────────────────────────────────────────────
        run_prioritize(claims_folder);

    } elif target_claim_id {
        # ── SINGLE MODE ────────────────────────────────────────────────────────
        # Read existing output; if absent, run agent once to create it
        result_json: str = load_output(target_claim_id);

        if not result_json {
            ::py::
            from rich.console import Console as _cs
            _cs().print(f"\n[bold]First run for [cyan]{target_claim_id}[/cyan] — processing now…[/bold]")
            ::py::
            claim_dir: str = f"{claims_folder}/{target_claim_id}";
            doc_contents = preprocess_claim_folder(claim_dir, target_claim_id);
            first_result: ClaimResult = ClaimResult();
            ::py::
            from rich.console import Console as _css
            with _css().status(f"Agent is processing {target_claim_id}...", spinner="dots"):
                pass
            ::py::
            first_result = process_claim(target_claim_id, doc_contents);
            result_json = serialize_result(first_result);
            save_result(target_claim_id, result_json);
            save_docs(target_claim_id, doc_contents);
        }

        display_result_dict(target_claim_id, result_json);

        # Enter interactive loop if agent is waiting for customer
        needs_chat: bool = False;
        ::py::
        import json as _jnc
        try:
            needs_chat = (_jnc.loads(result_json).get("next_action") or {}).get("type") == "MESSAGE_CUSTOMER"
        except Exception:
            needs_chat = False
        ::py::

        if needs_chat {
            run_interactive_loop(target_claim_id, result_json);
        }

    } else {
        # ── BATCH MODE ─────────────────────────────────────────────────────────
        # Read all existing outputs and display them. No agent calls.
        ::py::
        from rich.console import Console as _cb
        _cb().print(f"\n[bold]Claims in [cyan]{claims_folder}[/cyan][/bold]")
        ::py::

        claim_ids = list_claim_ids(claims_folder);

        if not claim_ids {
            ::py::
            from rich.console import Console as _cbn
            _cbn().print(f"[red]No claim folders found in {claims_folder}.[/red]")
            import sys; sys.exit(1)
            ::py::
        }

        all_result_jsons: list = [];
        missing_outputs: list = [];

        for cid in claim_ids {
            rj: str = load_output(cid);
            if rj {
                display_result_dict(cid, rj);
                all_result_jsons.append(rj);
            } else {
                missing_outputs.append(cid);
            }
        }

        if missing_outputs {
            ::py::
            from rich.console import Console as _cmiss
            _cmiss.print = _cmiss().print if not hasattr(_cmiss, 'print') else _cmiss.print
            from rich.console import Console as _cmiss2
            _cmiss2().print(f"\n[yellow]No output file found for: {', '.join(missing_outputs)}[/yellow]")
            _cmiss2().print("[dim]Run single mode to process them: jac src/main.jac <folder> <claim_id>[/dim]")
            ::py::
        }

        if not all_result_jsons {
            ::py::
            from rich.console import Console as _cnone
            _cnone().print("[red]No processed claims found in outputs/. Run single mode first.[/red]")
            import sys; sys.exit(1)
            ::py::
        }

        run_prioritize(claims_folder);
    }
}
