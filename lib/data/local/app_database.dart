import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppDatabase extends GeneratedDatabase {
  AppDatabase._(QueryExecutor executor) : super(executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo> get allTables => const [];

  static Future<AppDatabase> open({bool inMemory = false}) async {
    final executor = inMemory
        ? NativeDatabase.memory()
        : NativeDatabase(
            File(
              p.join(
                (await getApplicationDocumentsDirectory()).path,
                'questions.sqlite',
              ),
            ),
          );
    final database = AppDatabase._(executor);
    await database._init();
    return database;
  }

  Future<void> _init() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS questions (
        id TEXT PRIMARY KEY,
        category TEXT NOT NULL,
        year INTEGER NOT NULL,
        text TEXT NOT NULL,
        choices TEXT NOT NULL,
        answer_index INTEGER NOT NULL,
        explanation TEXT NOT NULL,
        source_url TEXT
      );
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS question_answers (
        question_id TEXT PRIMARY KEY,
        selected_index INTEGER,
        is_correct INTEGER NOT NULL DEFAULT 0,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_wrong INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  Future<int?> getSeedVersion() async {
    final rows = await customSelect(
      "SELECT value FROM meta WHERE key = 'seed_version'",
    ).get();
    if (rows.isEmpty) {
      return null;
    }
    return int.tryParse(rows.first.data['value'] as String? ?? '');
  }

  Future<String?> getMetaValue(String key) async {
    final rows = await customSelect(
      "SELECT value FROM meta WHERE key = ?",
      variables: [Variable.withString(key)],
    ).get();
    if (rows.isEmpty) return null;
    return rows.first.data['value'] as String?;
  }

  Future<void> setSeedVersion(int version) async {
    await customStatement(
      'INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [
        'seed_version',
        version.toString(),
      ],
    );
  }

  Future<void> setMetaValue(String key, String value) async {
    await customStatement(
      'INSERT INTO meta(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
      [
        key,
        value,
      ],
    );
  }

  Future<void> upsertQuestion({
    required String id,
    required String category,
    required int year,
    required String text,
    required String choices,
    required int answerIndex,
    required String explanation,
    String? sourceUrl,
  }) async {
    await customStatement(
      '''
        INSERT INTO questions(id, category, year, text, choices, answer_index, explanation, source_url)
        VALUES(?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          category = excluded.category,
          year = excluded.year,
          text = excluded.text,
          choices = excluded.choices,
          answer_index = excluded.answer_index,
          explanation = excluded.explanation,
          source_url = excluded.source_url
      ''',
      [
        id,
        category,
        year,
        text,
        choices,
        answerIndex,
        explanation,
        sourceUrl ?? '',
      ],
    );
  }

  Future<bool> questionExists(String id) async {
    final rows = await customSelect(
      'SELECT 1 FROM questions WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    return rows.isNotEmpty;
  }

  Future<List<QueryRow>> query(String sql, List<Variable> variables) {
    return customSelect(sql, variables: variables).get();
  }

  Stream<List<QueryRow>> watch(
      String sql, List<Variable> variables, Stream<void> changes) async* {
    yield await query(sql, variables);
    await for (final _ in changes) {
      yield await query(sql, variables);
    }
  }

  Future<void> upsertAnswer({
    required String questionId,
    required int? selectedIndex,
    required bool isCorrect,
    required bool isWrong,
    required bool isFavorite,
  }) async {
    await customStatement(
      '''
        INSERT INTO question_answers(question_id, selected_index, is_correct, is_favorite, is_wrong, updated_at)
        VALUES(?, ?, ?, ?, ?, ?)
        ON CONFLICT(question_id) DO UPDATE SET
          selected_index = excluded.selected_index,
          is_correct = excluded.is_correct,
          is_favorite = excluded.is_favorite,
          is_wrong = excluded.is_wrong,
          updated_at = excluded.updated_at
      ''',
      [
        questionId,
        selectedIndex,
        isCorrect,
        isFavorite,
        isWrong,
        DateTime.now().toIso8601String(),
      ],
    );
  }
}
