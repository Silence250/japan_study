"""
Utilities for validating, deduplicating, and writing seed JSON.
"""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple
import tempfile
import os


class ValidationError(Exception):
    pass


def validate_question(q: Dict[str, Any]) -> None:
    required = [
        "id",
        "category",
        "year",
        "text",
        "choices",
        "answerIndex",
        "explanation",
        "sourceUrl",
    ]
    missing = [key for key in required if key not in q]
    if missing:
        raise ValidationError(f"Missing keys: {missing} in question {q}")
    if not isinstance(q["year"], int):
        raise ValidationError(f"year must be int: {q}")
    if not isinstance(q["choices"], list) or not q["choices"]:
        raise ValidationError(f"choices must be non-empty list: {q}")
    if any(choice is None or not str(choice).strip() for choice in q["choices"]):
        raise ValidationError(f"choices contain empty/whitespace entries: {q}")
    if not isinstance(q["answerIndex"], int):
        raise ValidationError(f"answerIndex must be int: {q}")
    if not (0 <= q["answerIndex"] < len(q["choices"])):
        raise ValidationError(f"answerIndex invalid: {q}")


def validate_seed(seed: Dict[str, Any]) -> None:
    if "questions" not in seed or not isinstance(seed["questions"], list):
        raise ValidationError("Seed must have 'questions' list")
    if "generatedAt" in seed and seed["generatedAt"] is not None:
        if not isinstance(seed["generatedAt"], str):
            raise ValidationError("generatedAt must be a string when present")
    if "sourceSessions" in seed and seed["sourceSessions"] is not None:
        if not isinstance(seed["sourceSessions"], list) or not all(
            isinstance(s, str) for s in seed["sourceSessions"]
        ):
            raise ValidationError("sourceSessions must be a list of strings when present")
    for q in seed["questions"]:
        validate_question(q)


def repair_seed(seed: Dict[str, Any]) -> Tuple[Dict[str, Any], List[str]]:
    if not isinstance(seed, dict):
        return {"version": 1, "questions": []}, ["<invalid seed>"]
    questions = seed.get("questions", [])
    if not isinstance(questions, list):
        questions = []
    valid_questions: List[Dict[str, Any]] = []
    invalid_ids: List[str] = []
    for q in questions:
        try:
            validate_question(q)
        except ValidationError:
            qid = q.get("id") if isinstance(q, dict) else None
            invalid_ids.append(str(qid) if qid else "<missing id>")
            continue
        valid_questions.append(q)
    repaired = dict(seed)
    repaired["questions"] = valid_questions
    if "generatedAt" in repaired and repaired["generatedAt"] is not None:
        if not isinstance(repaired["generatedAt"], str):
            repaired.pop("generatedAt", None)
    if "sourceSessions" in repaired and repaired["sourceSessions"] is not None:
        if not isinstance(repaired["sourceSessions"], list) or not all(
            isinstance(s, str) for s in repaired["sourceSessions"]
        ):
            repaired.pop("sourceSessions", None)
    if not isinstance(repaired.get("version", 1), int):
        repaired["version"] = 1
    return repaired, invalid_ids


def load_seed(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as fh:
        return json.load(fh)


def write_seed_atomic(path: Path, seed: Dict[str, Any]) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", newline="\n") as fh:
        json.dump(seed, fh, ensure_ascii=False, indent=2)
    tmp.replace(path)


def merge_questions(
    existing: List[Dict[str, Any]],
    incoming: List[Dict[str, Any]],
    prefer_new: bool = False,
) -> Tuple[List[Dict[str, Any]], int, int]:
    merged: Dict[str, Dict[str, Any]] = {q["id"]: q for q in existing}
    added = 0
    replaced = 0
    for q in incoming:
        if q["id"] in merged:
            if prefer_new:
                merged[q["id"]] = q
                replaced += 1
        else:
            merged[q["id"]] = q
            added += 1
    return list(merged.values()), added, replaced


def merge_seed_files(
    existing_path: Path,
    incoming_path: Path,
    out_path: Path,
    prefer_new: bool = False,
) -> Tuple[int, int, Dict[str, Any], List[str]]:
    existing = load_seed(existing_path) if existing_path.exists() else {"version": 1, "questions": []}
    incoming = load_seed(incoming_path)
    existing, dropped_ids = repair_seed(existing)
    if dropped_ids:
        print(
            f"[warn] Dropped {len(dropped_ids)} invalid existing questions: {', '.join(dropped_ids)}"
        )
    validate_seed(incoming)
    merged_questions, added, replaced = merge_questions(
        existing.get("questions", []), incoming.get("questions", []), prefer_new=prefer_new
    )
    merged_generated_at = incoming.get("generatedAt") or existing.get("generatedAt")
    merged_source_sessions = incoming.get("sourceSessions") or existing.get("sourceSessions", [])
    merged_seed = {
        "version": max(existing.get("version", 1), incoming.get("version", 1)),
        "questions": merged_questions,
        "generatedAt": merged_generated_at,
        "sourceSessions": merged_source_sessions,
    }
    validate_seed(merged_seed)
    write_seed_atomic(out_path, merged_seed)
    return added, replaced, merged_seed, dropped_ids


def summarize(seed: Dict[str, Any]) -> Dict[str, Any]:
    per_year = Counter()
    per_category = Counter()
    for q in seed.get("questions", []):
        per_year[q["year"]] += 1
        per_category[q["category"]] += 1
    return {
        "total": len(seed.get("questions", [])),
        "per_year": dict(per_year),
        "per_category": dict(per_category),
    }

# ===== Backward-compatibility shims for scrape.py =====
# Keep existing scraper code working even after refactors.
class ValidationError(Exception):
    """Backward-compatible validation error used by scrape.py."""
    pass


def _load_seed_compat(path: str) -> Dict[str, Any]:
    p = Path(path)
    if not p.exists():
        return {"version": 1, "questions": []}
    try:
        with p.open("r", encoding="utf-8") as f:
            d = json.load(f)
        if not isinstance(d, dict):
            raise ValidationError("seed JSON must be an object")
        d.setdefault("version", 1)
        d.setdefault("questions", [])
        if not isinstance(d["questions"], list):
            raise ValidationError("seed.questions must be a list")
        return d
    except json.JSONDecodeError as e:
        raise ValidationError(f"Invalid JSON: {e}") from e


def _write_seed_atomic_compat(path: str, seed: Dict[str, Any]) -> None:
    p = Path(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replace
    fd, tmp = tempfile.mkstemp(prefix=p.name + ".", suffix=".tmp", dir=str(p.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            json.dump(seed, f, ensure_ascii=False, indent=2)
        os.replace(tmp, str(p))
    finally:
        try:
            if os.path.exists(tmp):
                os.remove(tmp)
        except Exception:
            pass


def write_seed(
    path: str,
    seed: Dict[str, Any] = None,
    *,
    version: int = None,
    questions: Iterable[Dict[str, Any]] = None,
    generated_at: str = None,
    source_sessions: Iterable[str] = None,
) -> None:
    """
    Backward-compatible name expected by scrape.py.
    Accepts either (path, seed_dict) or (path, version=?, questions=?).
    """
    p = Path(path)
    if seed is None:
        seed = {
            "version": version or 1,
            "questions": list(questions or []),
        }
        if generated_at is not None:
            seed["generatedAt"] = generated_at
        if source_sessions is not None:
            seed["sourceSessions"] = list(source_sessions)
    _write_seed_atomic_compat(p, seed)


class QuestionStore:
    """
    Backward-compatible store expected by scrape.py.

    Behavior:
    - If resume=True and out exists, load existing questions and dedup by id.
    - add_question ignores duplicates by default; can prefer_new to overwrite.
    """

    def __init__(self, out_path: str = "seed.json", resume: bool = False, prefer_new: bool = False):
        self.out_path = out_path
        self.prefer_new = prefer_new

        if resume and Path(out_path).exists():
            self.seed = _load_seed_compat(out_path)
        else:
            self.seed = {"version": 1, "questions": []}

        self._by_id: Dict[str, Dict[str, Any]] = {}
        for q in self.seed.get("questions", []):
            qid = q.get("id")
            if isinstance(qid, str) and qid:
                self._by_id[qid] = q
        self._sequence_per_year = Counter()

        self.added = 0
        self.replaced = 0
        self.skipped = 0

    def add_question(self, q: Dict[str, Any]) -> bool:
        qid = q.get("id")
        if not isinstance(qid, str) or not qid.strip():
            raise ValidationError("question.id is required")
        qid = qid.strip()

        if qid in self._by_id:
            if self.prefer_new:
                self._by_id[qid] = q
                self.replaced += 1
                return True
            self.skipped += 1
            return False

        self._by_id[qid] = q
        self.added += 1
        return True

    def add_questions(self, questions: List[Dict[str, Any]]) -> int:
        n = 0
        for q in questions:
            if self.add_question(q):
                n += 1
        return n

    def to_seed(self) -> Dict[str, Any]:
        # Preserve stable ordering: existing order first, then new ones.
        existing_ids = []
        for q in self.seed.get("questions", []):
            qid = q.get("id")
            if isinstance(qid, str) and qid in self._by_id:
                existing_ids.append(qid)

        # Add any new ids not in the help list
        all_ids = list(self._by_id.keys())
        new_ids = [i for i in all_ids if i not in existing_ids]

        merged = [self._by_id[i] for i in existing_ids] + [self._by_id[i] for i in new_ids]
        seed_obj: Dict[str, Any] = {
            "version": self.seed.get("version", 1),
            "questions": merged,
        }
        if "generatedAt" in self.seed:
            seed_obj["generatedAt"] = self.seed.get("generatedAt")
        if "sourceSessions" in self.seed:
            seed_obj["sourceSessions"] = self.seed.get("sourceSessions")
        return seed_obj

    def save(self) -> None:
        seed = self.to_seed()
        # If your refactor already has validate_seed, call it
        if "validate_seed" in globals() and callable(globals()["validate_seed"]):
            globals()["validate_seed"](seed)  # type: ignore
        write_seed(self.out_path, seed)

    def load_existing(self, path: Path) -> None:
        data = _load_seed_compat(str(path))
        self.seed = data
        self._by_id = {}
        for q in data.get("questions", []):
            qid = q.get("id")
            if isinstance(qid, str) and qid:
                self._by_id[qid] = q

    def add(self, q: Dict[str, Any]) -> bool:
        return self.add_question(q)

    def all_questions(self) -> List[Dict[str, Any]]:
        return list(self._by_id.values())

    def next_sequence(self, year: int) -> int:
        self._sequence_per_year[year] += 1
        return self._sequence_per_year[year]

    def stats(self) -> Dict[str, Any]:
        per_year = Counter()
        per_category = Counter()
        for q in self._by_id.values():
            per_year[q.get("year")] += 1
            per_category[q.get("category")] += 1
        return {"total": len(self._by_id), "per_year": dict(per_year), "per_category": dict(per_category)}
