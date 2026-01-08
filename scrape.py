"""
CLI entrypoint for extracting AP questions from the public website into the
Flutter seed JSON format.

Usage examples:
  python scrape.py --out data/questions_seed.json --sessions all
  python scrape.py --out data/questions_seed.json --sessions "2025春,2024春"
  python scrape.py --out data/questions_seed.json --sessions "2025春" --resume

This script is intentionally conservative:
- Throttles requests (default 1 req/sec).
- Retries with exponential backoff on 429/5xx/timeouts.
- Caches responses on disk to speed up reruns.
- Supports resume (merges existing JSON output and skips already-scraped
  questions by id/content hash).

Site specifics:
- Fill in SESSION_SOURCES with the session identifiers and start/API URLs for
  the target site.
- parser.py contains HTML/JSON parsing helpers; adjust the selectors/keys to
  fit the site's structure.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple

from client import HttpClient, RequestConfig
from parser import (
    SessionMeta,
    extract_questions_from_html,
    stable_question_id,
    era_to_gregorian,
)
from storage import QuestionStore, ValidationError, write_seed
from urllib.parse import parse_qsl, urlencode
import time
import re
import os
from bs4 import BeautifulSoup


BASE_URL = "https://www.ap-siken.com/apkakomon.php"

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Scrape AP questions to JSON seed")
    parser.add_argument("--out", required=True, help="Path to output JSON file")
    parser.add_argument(
        "--sessions",
        required=True,
        help='Session list: "all" or comma-separated labels (e.g., "2025春,2024春")',
    )
    parser.add_argument(
        "--list-sessions",
        action="store_true",
        help="List available sessions discovered from the site and exit",
    )
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Resume from existing output and cache; skip already scraped items",
    )
    parser.add_argument(
        "--max-requests",
        type=int,
        default=200,
        help="Safety cap for randomized sampling per session",
    )
    parser.add_argument(
        "--max-qno",
        type=int,
        default=80,
        help="Maximum qno to attempt when total question count cannot be parsed (AP-Siken)",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Disable HTTP cache (still throttles and retries)",
    )
    parser.add_argument(
        "--throttle",
        type=float,
        default=1.0,
        help="Seconds between requests (min throttle)",
    )
    parser.add_argument(
        "--debug-pages",
        action="store_true",
        default=True,
        help="Save request/response per qno into debug_pages (use --no-debug-pages to disable)",
    )
    parser.add_argument(
        "--no-debug-pages",
        action="store_false",
        dest="debug_pages",
        help="Disable saving request/response per qno",
    )
    return parser.parse_args()


def resolve_sessions(arg_value: str, discovered: Dict[str, SessionMeta]) -> List[SessionMeta]:
    if arg_value.lower() == "all":
        return list(discovered.values())
    labels = [s.strip() for s in arg_value.split(",") if s.strip()]
    missing = [lbl for lbl in labels if lbl not in discovered]
    if missing:
        raise SystemExit(f"Unknown sessions: {', '.join(missing)}")
    return [discovered[lbl] for lbl in labels]


def discover_sessions(client: HttpClient) -> Dict[str, SessionMeta]:
    html = client.fetch(RequestConfig(url=BASE_URL))
    soup = BeautifulSoup(html, "html.parser")
    sessions: Dict[str, SessionMeta] = {}
    for inp in soup.select('input[name="times[]"]'):
        code = inp.get("value")
        if not code:
            continue
        label_text = ""
        if inp.parent and inp.parent.name == "label":
            label_text = inp.parent.get_text(strip=True)
        elif inp.next_sibling:
            label_text = str(inp.next_sibling).strip()
        try:
            year = era_to_gregorian(label_text)
        except Exception:
            continue
        sm = SessionMeta(label=label_text, year=year, times_code=code, base_url=BASE_URL)
        sessions[label_text] = sm
    return sessions


def extract_sid(html: str) -> str:
    m = re.search(r'name="sid" value="([a-f0-9]+)"', html)
    if not m:
        print("[debug] sid not found in start page")
        raise SystemExit("sid not found in start page")
    return m.group(1)


def build_post_data(
    times_code: str,
    sid: str,
    qno: int,
    start_time: str,
    q_param: str = "",
    r_param: str = "",
    c_param: str = "",
    result_value: str = "0",
) -> List[Tuple[str, str]]:
    pairs: List[Tuple[str, str]] = []
    pairs.append(("times[]", times_code))
    # Interleave fields with their category ranges as per captured payload.
    pairs.append(("fields[]", "te_all"))
    for cat in range(1, 14):
        pairs.append(("categories[]", str(cat)))
    pairs.append(("fields[]", "ma_all"))
    for cat in range(14, 17):
        pairs.append(("categories[]", str(cat)))
    pairs.append(("fields[]", "st_all"))
    for cat in range(17, 24):
        pairs.append(("categories[]", str(cat)))
    pairs.extend(
        [
            ("options[]", "timesFilter"),
            ("moshi", "mix_all"),
            ("moshi_cnt", "40"),
            ("addition", "0"),
            ("mode", "1"),
            ("qno", str(qno)),
            ("sid", sid),
            ("result", result_value or "-1"),
            ("checkflag", "-1"),
            ("startTime", start_time),
            ("_q", q_param),
            ("_r", r_param),
            ("_c", c_param),
        ]
    )
    return pairs


def debug_save(html: str, label: str, qno: int, reason: str, extension: str = ".html") -> None:
    safe_label = label.replace(" ", "_")
    out_dir = Path("debug_pages")
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{safe_label}_qno{qno}{extension}"
    mode = "w"
    encoding = "utf-8" if isinstance(html, str) else None
    with path.open(mode, encoding=encoding) as fh:
        fh.write(html)
    print(f"[debug] saved {path} (reason: {reason})")


def fetch_question_page(
    client: HttpClient,
    session: SessionMeta,
    sid: str,
    qno: int,
    start_time: str,
    q_param: str = "",
    r_param: str = "",
    c_param: str = "",
    result_value: str = "0",
    save_debug: bool = False,
) -> Tuple[int, str, Optional[bytes]]:
    data = build_post_data(
        session.times_code, sid, qno, start_time, q_param, r_param, c_param, result_value
    )
    # Sanity checks per request
    assert any(k == "result" and v == "0" for k, v in data), "result must be 0"
    if save_debug:
        debug_save(
            urlencode(data, doseq=True),
            session.label,
            qno,
            reason="request",
            extension=".request.txt",
        )
    status, content, body = client.fetch(
        RequestConfig(
            url=BASE_URL,
            method="POST",
            data=data,
            headers={"Referer": BASE_URL},
            cache_key=f"{sid}-{qno}",
            return_response=True,
        )
    )
    if save_debug:
        debug_save(
            content if isinstance(content, str) else str(content),
            session.label,
            qno,
            reason="response",
            extension=".response.html",
        )
    return status, content, body


def scrape_session(
    client: HttpClient,
    session: SessionMeta,
    store: QuestionStore,
    max_qno: int,
    save_html: bool,
) -> None:
    print(f"==> Session: {session.label} (year={session.year})")

    start_html = client.fetch(RequestConfig(url=BASE_URL))
    sid = extract_sid(start_html)
    start_time = str(int(time.time()))
    print(f"Extracted sid: {sid} start_time: {start_time}")

    q_param = ""
    r_param = ""
    c_param = ""
    result_value = "0"

    def handle_html(html: str, idx: int) -> None:
        marker = f"第{idx+1}問"
        found_marker = marker in html
        page_no = None
        m = re.search(r"第(\d+)問", html)
        if m:
            page_no = int(m.group(1))
        print(f"qno={idx} marker_found={found_marker} page_no={page_no}")
        if not found_marker:
            debug_save(html, session.label, idx, reason="still config page")
            return
        questions = extract_questions_from_html(html, session)
        if not questions:
            debug_save(html, session.label, idx, reason="parse returned 0")
            return
        for q in questions:
            if q.get("id") is None:
                q["id"] = stable_question_id(session.year, store.next_sequence(session.year))
            if q.get("answerIndex") == -1:
                print(f"Warning: missing answer for qno {idx} ({q['id']}); set to -1")
            store.add(q)

    def parse_hidden_params(html: str) -> Tuple[str, str, str, str]:
        from bs4 import BeautifulSoup

        soup = BeautifulSoup(html, "html.parser")
        q_val = soup.find("input", attrs={"name": "_q"})
        r_val = soup.find("input", attrs={"name": "_r"})
        c_val = soup.find("input", attrs={"name": "_c"})
        res_val = soup.find("input", attrs={"name": "result"})
        return (
            q_val["value"] if q_val and q_val.has_attr("value") else "",
            r_val["value"] if r_val and r_val.has_attr("value") else "",
            c_val["value"] if c_val and c_val.has_attr("value") else "",
            res_val["value"] if res_val and res_val.has_attr("value") else "-1",
        )

    for idx in range(max_qno):
        qno_value = idx
        attempts = 0
        while attempts < 3:
            status, html, body = fetch_question_page(
                client,
                session,
                sid,
                qno_value,
                start_time,
                q_param,
                r_param,
                c_param,
                result_value,
                save_debug=save_html,
            )
            print(f"qno={qno_value} status={status} len={len(html)} attempt={attempts+1}")
            handle_html(html, idx)
            if f"第{idx+1}問" in html:
                # Update hidden params for next request.
                q_param, r_param, c_param, result_value = parse_hidden_params(html)
                # Force result to 0 for subsequent sends.
                result_value = "0"
                break
            attempts += 1
            time.sleep(1)
        if attempts == 3 and f"第{idx+1}問" not in html:
            print(f"[warn] qno={qno_value} still config after retries")

    print(f"Added {len(store.all_questions())} questions so far for {session.label}")


def main() -> None:
    args = parse_args()
    out_path = Path(args.out)
    os.makedirs(out_path.parent, exist_ok=True)

    client = HttpClient(
        cache_enabled=not args.no_cache,
        throttle_seconds=args.throttle,
    )
    discovered = discover_sessions(client)
    if args.list_sessions:
        print("Discovered sessions:")
        for lbl, sm in discovered.items():
            print(f"- {lbl} ({sm.times_code}) year={sm.year}")
        return

    sessions = resolve_sessions(args.sessions, discovered)

    store = QuestionStore()
    if args.resume and out_path.exists():
        print(f"Resuming from existing output: {out_path}")
        store.load_existing(out_path)

    for session in sessions:
        scrape_session(
            client, session, store, max_qno=args.max_qno, save_html=args.debug_pages
        )

    try:
        write_seed(out_path, version=1, questions=store.all_questions())
    except ValidationError as exc:
        print(f"Validation failed: {exc}")
        sys.exit(1)

    totals = store.stats()
    print("\nScrape complete.")
    print(f"Total questions: {totals['total']}")
    print("Per-year:")
    for year, count in totals["per_year"].items():
        print(f"  {year}: {count}")
    print("Per-category:")
    for cat, count in totals["per_category"].items():
        print(f"  {cat}: {count}")


if __name__ == "__main__":
    main()
