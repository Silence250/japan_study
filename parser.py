"""
Parsing helpers for AP question pages / APIs.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Tuple

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
CHOICE_IDS = ("select_a", "select_i", "select_u", "select_e")
CHOICE_LABELS = ("ア", "イ", "ウ", "エ")


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


def _extract_choices_from_list(soup: BeautifulSoup) -> List[str]:
    items = soup.select(".selectList li")
    if len(items) < len(CHOICE_LABELS):
        return []
    choices: List[str] = []
    for li in items[: len(CHOICE_LABELS)]:
        choice_text = ""
        for child in li.find_all(["span", "div", "p"], recursive=False):
            text = child.get_text(" ", strip=True)
            if text:
                choice_text = text
                break
        if not choice_text:
            button = li.find("button", class_="selectBtn")
            label = button.get_text(" ", strip=True) if button else ""
            raw = li.get_text(" ", strip=True)
            if label and raw.startswith(label):
                raw = raw[len(label) :].strip()
            choice_text = raw
        choices.append(choice_text)
    return choices


def _extract_choices(soup: BeautifulSoup) -> List[str]:
    choices: List[str] = []
    found_any = False
    for choice_id in CHOICE_IDS:
        el = soup.select_one(f"#{choice_id}")
        if el:
            found_any = True
            choices.append(el.get_text(" ", strip=True))
        else:
            choices.append("")
    # Some pages render choices without select_* ids (or as images). Fallback to list text.
    if not found_any or any(not choice.strip() for choice in choices):
        fallback = _extract_choices_from_list(soup)
        if fallback:
            choices = fallback
    return choices


def extract_questions_from_html(html: str, session: SessionMeta) -> List[Dict[str, Any]]:
    soup = BeautifulSoup(html, "html.parser")

    siken_question = soup.select_one(".selectList")
    if not siken_question:
        return []

    question_text = None
    text_div = soup.select_one("h3.qno + div")
    if text_div:
        question_text = text_div.get_text(" ", strip=True)

    choices = _extract_choices(soup)

    answer_char = soup.select_one("#answerChar")
    answer_char_text = answer_char.get_text(strip=True) if answer_char else ""
    char_to_index = {"ア": 0, "イ": 1, "ウ": 2, "エ": 3}
    answer_index = char_to_index.get(answer_char_text, -1)
    choices, answer_index = _sanitize_choices(choices, answer_index)

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


def _sanitize_choices(choices: List[str], answer_index: int) -> Tuple[List[str], int]:
    cleaned: List[str] = []
    new_answer_index: Optional[int] = None
    for idx, choice in enumerate(choices):
        trimmed = choice.strip()
        if not trimmed:
            continue
        if idx == answer_index:
            new_answer_index = len(cleaned)
        cleaned.append(trimmed)
    if new_answer_index is None:
        return cleaned, -1
    return cleaned, new_answer_index


def parse_total_questions(html: str) -> Optional[int]:
    m = re.search(r"選択中の問題(\d+)問", html)
    if m:
        return int(m.group(1))
    return None
