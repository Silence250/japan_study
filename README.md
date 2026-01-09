## AP Question Extractor

Python toolchain to scrape a public AP past-question site and export data into the Flutter app seed JSON format.

### Files
- `scrape.py` — CLI entrypoint.
- `client.py` — HTTP client with throttle/retry/cache.
- `parser.py` — HTML/JSON parsers and normalization helpers (era/year conversion, category mapping).
- `storage.py` — Validation, deduplication, and JSON writer.

### Prerequisites
- Python 3.10+
- Install deps:
  ```bash
  pip install requests beautifulsoup4
  # Optional (only if you wire it in): playwright
  ```

### Configure sessions
Edit `SESSION_SOURCES` in `scrape.py` with the site’s sessions and URLs:
```python
SESSION_SOURCES = {
    "2025春": SessionMeta(
        label="2025春",
        year=2025,
        start_url="https://example.com/ap/questions?session=2025_spring",
        api_url="https://example.com/api/questions?session=2025_spring",  # if available
        category="network",  # optional default
    ),
}
```
- Prefer `api_url` if the site exposes a deterministic JSON/XHR endpoint.
- If only randomized HTML is available, provide `start_url`; the scraper will sample until convergence.

### Era conversion
`parser.py` converts Japanese era labels:
- 令和N → 2018 + N
- 平成N → 1988 + N

### Running
```bash
python scrape.py --out data/questions_seed.json --sessions all
python scrape.py --out data/questions_seed.json --sessions "2025春,2024春"
python scrape.py --out data/questions_seed.json --sessions "2025春" --resume
# AP-Siken (令和7年春期, Windows PowerShell examples)
python scrape.py --sessions "令和7年春期" --out tmp.json --max-qno 2 --throttle 1.0
```

Flags:
- `--resume` merges existing output and cache; skips already-seen questions.
- `--max-requests` caps sampling requests per session (for randomized endpoints).
- `--max-qno` caps AP-Siken qno loop when total question count cannot be parsed.
- `--throttle` seconds between requests (default 1s).
- `--no-cache` to disable HTTP caching.

### Validation & reporting
- The writer validates required fields and `answerIndex` bounds before saving.
- Prints totals plus per-year and per-category counts.
- Fails fast on missing fields.
- Validate the current seed: `python3 tools/validate_seed.py --path assets/questions_seed.json`
- Merge behavior test: `python3 -m unittest tools/test_update_seed_merge.py`

### Seed metadata
- The seed JSON now includes `generatedAt` (ISO-8601) and `sourceSessions` at the root.
- The Flutter app auto-imports when `generatedAt` differs from the last imported value, preserving user progress and showing a small in-app notice.

### Update & install helpers
- Cross-platform updater: `python tools/update_seed.py --sessions "令和7年春期"`  
  - Optional install/restart Android: add `--run` (and `--adb <path>` if needed).
  - Optional clear data (dev-only): `--clear-data`
  - Defaults to prefer new data on ID collisions; pass `--prefer-existing` to keep old.
  - Override package: `--package com.example.app`
  - Override flutter: `--flutter C:\path\to\flutter.bat` (skips run if not found)
- PowerShell wrapper:  
  `powershell -NoProfile -ExecutionPolicy Bypass -File tools/update_seed.ps1 -Sessions "令和7年春期" [-Run] [-ClearData]`
- The updater merges into `assets/questions_seed.json`, keeps existing progress, and only refreshes DB when metadata changed.

### Adapting parsing
- For JSON: adjust keys in `parse_questions_from_json`.
- For HTML: adjust selectors in `extract_questions_from_html` (look for question text, choices, answer).
- Ensure `sourceUrl` points to the canonical page or session start URL.

### Output schema (exact)
```json
{
  "version": 1,
  "questions": [
    {
      "id": "ap-2024-q001",
      "category": "network",
      "year": 2024,
      "text": "...",
      "choices": ["...", "...", "...", "..."],
      "answerIndex": 0,
      "explanation": "...",
      "sourceUrl": "https://..."
    }
  ]
}
```
