"""
Parsing helpers for AP question pages / APIs.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from bs4 import BeautifulSoup


@dataclass
class SessionMeta:
    label: str
    year: int
    times_code: str
    category: Optional[str] = None
    base_url: Optional[str] = None


ERA_PATTERNS = {
    "令和": 2018,
    "平成": 1988,
    "昭和": 1925,
}


def era_to_gregorian(label: str) -> int:
    for era, offset in ERA_PATTERNS.items():
        if era in label:
            digits = re.findall(r"\d+", label)
            if digits:
                return offset + int(digits[0])
    digits = re.findall(r"\d{4}", label)
    if digits:
        return int(digits[0])
    raise ValueError(f"Unable to parse year from label: {label}")


def normalize_category(raw: Optional[str]) -> str:
    if not raw:
        return "unknown"
    text = raw.lower()
    if "network" in text or "ネット" in raw:
        return "network"
    if "sec" in text or "セキュ" in raw:
        return "security"
    if "db" in text or "data" in text or "データ" in raw:
        return "database"
    if "manage" in text or "project" in text or "マネジ" in raw:
        return "management"
    return raw.strip() or "unknown"


def stable_question_id(year: int, sequence: int) -> str:
    return f"ap-{year}-q{sequence:03d}"


def _extract_category_path(soup: BeautifulSoup) -> List[str]:
    h3 = soup.find("h3", string=lambda s: s and "分類" in s)
    if not h3:
        return []
    div = h3.find_next("div")
    if not div:
        return []
    text = div.get_text(" ", strip=True)
    # Normalize separators
    text = text.replace("&raquo;", "»").replace("＞", "»").replace("»", " » ")
    parts = [p.strip() for p in re.split(r"\s*»\s*", text) if p.strip()]
    return parts


def extract_questions_from_html(html: str, session: SessionMeta) -> List[Dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")

    siken_question = soup.select_one(".selectList")
    if not siken_question:
        return []

    question_text = None
    text_div = soup.select_one("h3.qno + div")
    if text_div:
        question_text = text_div.get_text(" ", strip=True)

    choices: List[str] = []
    for choice_id in ("select_a", "select_i", "select_u", "select_e"):
        el = soup.select_one(f"#{choice_id}")
        choices.append(el.get_text(" ", strip=True) if el else "")

    answer_char = soup.select_one("#answerChar")
    answer_char_text = answer_char.get_text(strip=True) if answer_char else ""
    char_to_index = {"ア": 0, "イ": 1, "ウ": 2, "エ": 3}
    answer_index = char_to_index.get(answer_char_text, -1)

    explanation_el = soup.select_one("#kaisetsu")
    explanation = explanation_el.get_text(" ", strip=True) if explanation_el else ""

    meta_url = soup.find("meta", attrs={"property": "og:url"})
    source_url = (
        meta_url["content"]
        if meta_url and meta_url.has_attr("content")
        else session.base_url
        or ""
    )

    category_path = _extract_category_path(soup)
    category = " » ".join(category_path) if category_path else "unknown"

    hid_q = soup.find("input", attrs={"name": "_q"})
    q_number = None
    if hid_q and hid_q.has_attr("value"):
        parts = hid_q["value"].split("_")
        if parts and parts[-1].isdigit():
            q_number = int(parts[-1])

    question_id = None
    if q_number is not None:
        question_id = stable_question_id(session.year, q_number)

    return [
        {
            "id": question_id,
            "category": category,
            "categoryPath": category_path if category_path else [],
            "year": session.year,
            "text": question_text,
            "choices": choices,
            "answerIndex": answer_index,
            "explanation": explanation,
            "sourceUrl": source_url,
        }
    ]


def parse_total_questions(html: str) -> Optional[int]:
    m = re.search(r"選択中の問題(\d+)問", html)
    if m:
        return int(m.group(1))
    return None
