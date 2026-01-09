import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import '../models/question.dart';
import 'local/app_database.dart';

class CategorySummary {
  const CategorySummary({required this.category, required this.count});

  final String category;
  final int count;
}

class YearSummary {
  const YearSummary({required this.year, required this.count});

  final int year;
  final int count;
}

class AnswerState {
  const AnswerState({
    required this.selectedIndex,
    required this.isCorrect,
    required this.isFavorite,
    required this.isWrong,
  });

  final int? selectedIndex;
  final bool isCorrect;
  final bool isFavorite;
  final bool isWrong;
}

class QuestionWithState {
  const QuestionWithState({required this.question, required this.answerState});

  final Question question;
  final AnswerState answerState;
}

class ProgressSummary {
  const ProgressSummary({
    required this.total,
    required this.answered,
    required this.correct,
  });

  final int total;
  final int answered;
  final int correct;
}

class SeedRefreshResult {
  const SeedRefreshResult({
    required this.years,
    required this.inserted,
    required this.sourceSessions,
    this.generatedAt,
    required this.updated,
  });

  final List<int> years;
  final int inserted;
  final List<String> sourceSessions;
  final String? generatedAt;
  final bool updated;
}

class QuestionRepository {
  QuestionRepository(this._database);

  final AppDatabase _database;
  final StreamController<void> _changes = StreamController.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<SeedRefreshResult> ensureSeeded() async {
    final jsonString = await rootBundle.loadString(
      'assets/questions_seed.json',
    );
    final seed = QuestionsSeed.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
    final currentVersion = await _database.getSeedVersion();
    final storedGeneratedAt =
        await _database.getMetaValue('seed_generated_at');
    final sameGeneratedAt = seed.generatedAt != null &&
        storedGeneratedAt != null &&
        storedGeneratedAt == seed.generatedAt;
    if (sameGeneratedAt ||
        (seed.generatedAt == null &&
            currentVersion != null &&
            currentVersion >= seed.version)) {
      return SeedRefreshResult(
        years: const [],
        inserted: 0,
        sourceSessions: seed.sourceSessions,
        generatedAt: seed.generatedAt,
        updated: false,
      );
    }
    return _importSeed(seed, previousGeneratedAt: storedGeneratedAt);
  }

  Future<void> seedFromQuestions(QuestionsSeed seed) async {
    for (final question in seed.questions) {
      await _database.upsertQuestion(
        id: question.id,
        category: question.category,
        year: question.year,
        text: question.text,
        choices: Question.encodeChoices(question.choices),
        answerIndex: question.answerIndex,
        explanation: question.explanation,
        sourceUrl: question.sourceUrl,
      );
    }
    await _database.setSeedVersion(seed.version);
    _changes.add(null);
  }

  Stream<List<CategorySummary>> watchCategories() {
    return _database
        .watch(
          'SELECT category, COUNT(*) as count FROM questions GROUP BY category ORDER BY category',
          const [],
          changes,
        )
        .map((rows) {
          return rows
              .map(
                (row) => CategorySummary(
                  category: row.data['category'] as String,
                  count: row.data['count'] as int,
                ),
              )
              .toList();
        });
  }

  Stream<List<YearSummary>> watchYears(String category) {
    return _database
        .watch(
          'SELECT year, COUNT(*) as count FROM questions WHERE category = ? GROUP BY year ORDER BY year DESC',
          [Variable.withString(category)],
          changes,
        )
        .map((rows) {
          return rows
              .map(
                (row) => YearSummary(
                  year: row.data['year'] as int,
                  count: row.data['count'] as int,
                ),
              )
              .toList();
        });
  }

  Stream<List<QuestionWithState>> watchQuestions(String category, int year) {
    return _database
        .watch(
          '''
        SELECT q.id, q.category, q.year, q.text, q.choices, q.answer_index, q.explanation, q.source_url,
               a.selected_index, a.is_correct, a.is_favorite, a.is_wrong
        FROM questions q
        LEFT JOIN question_answers a ON q.id = a.question_id
        WHERE q.category = ? AND q.year = ?
        ORDER BY q.id
      ''',
          [Variable.withString(category), Variable.withInt(year)],
          changes,
        )
        .map((rows) => rows.map(_mapQuestionRow).toList());
  }

  Future<List<QuestionWithState>> searchQuestions(String query) async {
    final rows = await _database.query(
      '''
        SELECT q.id, q.category, q.year, q.text, q.choices, q.answer_index, q.explanation, q.source_url,
               a.selected_index, a.is_correct, a.is_favorite, a.is_wrong
        FROM questions q
        LEFT JOIN question_answers a ON q.id = a.question_id
        WHERE q.text LIKE ? OR q.explanation LIKE ?
        ORDER BY q.year DESC
      ''',
      [Variable.withString('%$query%'), Variable.withString('%$query%')],
    );
    return rows.map(_mapQuestionRow).toList();
  }

  Stream<List<QuestionWithState>> watchFavorites() {
    return _database
        .watch(
          '''
        SELECT q.id, q.category, q.year, q.text, q.choices, q.answer_index, q.explanation, q.source_url,
               a.selected_index, a.is_correct, a.is_favorite, a.is_wrong
        FROM questions q
        JOIN question_answers a ON q.id = a.question_id
        WHERE a.is_favorite = 1
        ORDER BY q.year DESC
      ''',
          const [],
          changes,
        )
        .map((rows) => rows.map(_mapQuestionRow).toList());
  }

  Stream<List<QuestionWithState>> watchWrongAnswers() {
    return _database
        .watch(
          '''
        SELECT q.id, q.category, q.year, q.text, q.choices, q.answer_index, q.explanation, q.source_url,
               a.selected_index, a.is_correct, a.is_favorite, a.is_wrong
        FROM questions q
        JOIN question_answers a ON q.id = a.question_id
        WHERE a.is_wrong = 1
        ORDER BY q.year DESC
      ''',
          const [],
          changes,
        )
        .map((rows) => rows.map(_mapQuestionRow).toList());
  }

  Future<ProgressSummary> fetchProgress(String category, int year) async {
    final totalRows = await _database.query(
      'SELECT COUNT(*) as total FROM questions WHERE category = ? AND year = ?',
      [Variable.withString(category), Variable.withInt(year)],
    );
    final total = totalRows.first.data['total'] as int;
    final answeredRows = await _database.query(
      '''
        SELECT COUNT(*) as answered,
               SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END) as correct
        FROM question_answers a
        JOIN questions q ON q.id = a.question_id
        WHERE q.category = ? AND q.year = ? AND a.selected_index IS NOT NULL
      ''',
      [Variable.withString(category), Variable.withInt(year)],
    );
    final answered = answeredRows.first.data['answered'] as int? ?? 0;
    final correct = answeredRows.first.data['correct'] as int? ?? 0;
    return ProgressSummary(total: total, answered: answered, correct: correct);
  }

  Stream<ProgressSummary> watchProgress(String category, int year) async* {
    // emit initial
    yield await fetchProgress(category, year);
    await for (final _ in _changes.stream) {
      yield await fetchProgress(category, year);
    }
  }

  Future<void> saveAnswer(Question question, int selectedIndex) async {
    final existing = await _database.query(
      'SELECT is_favorite FROM question_answers WHERE question_id = ?',
      [Variable.withString(question.id)],
    );
    final isFavorite =
        existing.isNotEmpty && (existing.first.data['is_favorite'] as int) == 1;
    final isCorrect = selectedIndex == question.answerIndex;
    await _database.upsertAnswer(
      questionId: question.id,
      selectedIndex: selectedIndex,
      isCorrect: isCorrect,
      isWrong: !isCorrect,
      isFavorite: isFavorite,
    );
    _changes.add(null);
  }

  Future<SeedRefreshResult> refreshFromSeed() async {
    final storedGeneratedAt =
        await _database.getMetaValue('seed_generated_at');
    final jsonString = await rootBundle.loadString(
      'assets/questions_seed.json',
    );
    final seed = QuestionsSeed.fromJson(
      jsonDecode(jsonString) as Map<String, dynamic>,
    );
    final result =
        await _importSeed(seed, previousGeneratedAt: storedGeneratedAt);
    return result;
  }

  Future<void> toggleFavorite(Question question, bool isFavorite) async {
    final existing = await _database.query(
      'SELECT selected_index, is_correct, is_wrong FROM question_answers WHERE question_id = ?',
      [Variable.withString(question.id)],
    );
    final selectedIndex = existing.isNotEmpty
        ? existing.first.data['selected_index'] as int?
        : null;
    final isCorrect =
        existing.isNotEmpty && (existing.first.data['is_correct'] as int) == 1;
    final isWrong =
        existing.isNotEmpty && (existing.first.data['is_wrong'] as int) == 1;
    await _database.upsertAnswer(
      questionId: question.id,
      selectedIndex: selectedIndex,
      isCorrect: isCorrect,
      isWrong: isWrong,
      isFavorite: isFavorite,
    );
    _changes.add(null);
  }

  QuestionWithState _mapQuestionRow(dynamic row) {
    final data = row.data as Map<String, Object?>;
    final rawChoices = Question.decodeChoices(data['choices'] as String);
    final sanitizedAnswerIndex = Question.sanitizeChoices(
      rawChoices,
      data['answer_index'] as int,
      questionId: data['id'] as String?,
    );
    final question = Question(
      id: data['id'] as String,
      category: data['category'] as String,
      year: data['year'] as int,
      text: data['text'] as String,
      choices: rawChoices,
      answerIndex: sanitizedAnswerIndex,
      explanation: data['explanation'] as String,
      sourceUrl: (data['source_url'] as String?)?.isEmpty == true
          ? null
          : data['source_url'] as String?,
    );
    final selectedIndex = data['selected_index'] as int?;
    final isCorrect = (data['is_correct'] as int? ?? 0) == 1;
    final isFavorite = (data['is_favorite'] as int? ?? 0) == 1;
    final isWrong = (data['is_wrong'] as int? ?? 0) == 1;
    final answerState = AnswerState(
      selectedIndex: selectedIndex,
      isCorrect: isCorrect,
      isFavorite: isFavorite,
      isWrong: isWrong,
    );
    return QuestionWithState(question: question, answerState: answerState);
  }

  Future<void> dispose() async {
    await _changes.close();
    await _database.close();
  }

  Future<SeedRefreshResult> _importSeed(
    QuestionsSeed seed, {
    String? previousGeneratedAt,
  }) async {
    final years = <int>{};
    var inserted = 0;
    for (final question in seed.questions) {
      years.add(question.year);
      final exists = await _database.questionExists(question.id);
      await _database.upsertQuestion(
        id: question.id,
        category: question.category,
        year: question.year,
        text: question.text,
        choices: Question.encodeChoices(question.choices),
        answerIndex: question.answerIndex,
        explanation: question.explanation,
        sourceUrl: question.sourceUrl,
      );
      if (!exists) {
        inserted++;
      }
    }
    await _database.setSeedVersion(seed.version);
    if (seed.generatedAt != null) {
      await _database.setMetaValue('seed_generated_at', seed.generatedAt!);
    }
    if (seed.sourceSessions.isNotEmpty) {
      await _database.setMetaValue(
        'seed_source_sessions',
        seed.sourceSessions.join(','),
      );
    }
    _changes.add(null);
    final updated = inserted > 0 ||
        (seed.generatedAt != null &&
            seed.generatedAt != previousGeneratedAt);
    final sortedYears = years.toList()..sort();
    return SeedRefreshResult(
      years: sortedYears,
      inserted: inserted,
      sourceSessions: seed.sourceSessions,
      generatedAt: seed.generatedAt,
      updated: updated,
    );
  }
}
