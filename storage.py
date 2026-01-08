"""
Utilities for validating, deduplicating, and writing seed JSON.
"""

from __future__ import annotations

import json
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple


class ValidationError(Exception):
    pass


def validate_question(q: Dict[str, Any]) -> None:
    required = ["id", "category", "year", "text", "choices", "answerIndex", "explanation", "sourceUrl"]
    missing = [key for key in required if key not in q]
    if missing:
        raise ValidationError(f"Missing keys: {missing} in question {q}")
    if not isinstance(q["year"], int):
        raise ValidationError(f"year must be int: {q}")
    if not isinstance(q["choices"], list) or not q["choices"]:
        raise ValidationError(f"choices must be non-empty list: {q}")
    if not isinstance(q["answerIndex"], int):
        raise ValidationError(f"answerIndex must be int: {q}")
    if q["answerIndex"] != -1 and not (0 <= q["answerIndex"] < len(q["choices"])):
        raise ValidationError(f"answerIndex invalid: {q}")


def make_hash(q: Dict[str, Any]) -> str:
    key = (q.get("text") or "") + "|" + "|".join(q.get("choices") or [])
    return str(hash(key))


class QuestionStore:
    def __init__(self) -> None:
        self.questions: Dict[str, Dict[str, Any]] = {}
        self.hashes: Set[str] = set()
        self._sequence_per_year: Counter[int] = Counter()

    def load_existing(self, path: Path) -> None:
        with path.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        for q in data.get("questions", []):
            self.add(q, allow_duplicate_id=True)

    def add(self, q: Dict[str, Any], allow_duplicate_id: bool = False) -> bool:
        """
        Add question if new. Returns True when added.
        """
        if q.get("id") in self.questions and not allow_duplicate_id:
            return False
        content_hash = make_hash(q)
        if content_hash in self.hashes:
            return False
        try:
            validate_question(q)
        except ValidationError as exc:
            print(f"[validation] rejected: {exc}")
            return False
        self.hashes.add(content_hash)
        self.questions[q["id"]] = q
        return True

    def all_questions(self) -> List[Dict[str, Any]]:
        return list(self.questions.values())

    def stats(self) -> Dict[str, Any]:
        per_year = Counter()
        per_category = Counter()
        for q in self.questions.values():
            per_year[q["year"]] += 1
            per_category[q["category"]] += 1
        return {
            "total": len(self.questions),
            "per_year": dict(per_year),
            "per_category": dict(per_category),
        }

    def next_sequence(self, year: int) -> int:
        self._sequence_per_year[year] += 1
        return self._sequence_per_year[year]


def write_seed(path: Path, version: int, questions: Iterable[Dict[str, Any]]) -> None:
    validated: List[Dict[str, Any]] = []
    for q in questions:
        validate_question(q)
        validated.append(q)
    payload = {"version": version, "questions": validated}
    with path.open("w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=2)
