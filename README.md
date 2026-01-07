# japan_study

## Flutter question bank app

The Flutter app lives in `/flutter_app` and uses a local SQLite database (Drift) to store all questions for offline use.

### Run locally

```bash
cd flutter_app
flutter pub get
flutter run
```

### Run on iOS/Android

```bash
cd flutter_app
flutter pub get
flutter run -d ios
flutter run -d android
```

### Add more questions

1. Edit `data/questions_seed.json` using the schema below.
2. Copy the updated file into `flutter_app/assets/questions_seed.json`.
3. Bump the `version` field to trigger re-import on next launch.

### Data schema

```json
{
  "version": 1,
  "questions": [
    {
      "id": "ap-2024-q001",
      "category": "network",
      "year": 2024,
      "text": "...",
      "choices": ["A", "B", "C", "D"],
      "answerIndex": 2,
      "explanation": "...",
      "sourceUrl": "optional"
    }
  ]
}
```