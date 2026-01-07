import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/question.dart';
import 'local/app_database.dart';
import 'question_repository.dart';

class QuestionService {
  QuestionService(this._repository);

  final QuestionRepository _repository;

  Future<void> ensureSeeded() => _repository.ensureSeeded();

  Stream<List<CategorySummary>> watchCategories() =>
      _repository.watchCategories();

  Stream<List<YearSummary>> watchYears(String category) =>
      _repository.watchYears(category);

  Stream<List<QuestionWithState>> watchQuestions(String category, int year) {
    return _repository.watchQuestions(category, year);
  }

  Stream<List<QuestionWithState>> watchFavorites() =>
      _repository.watchFavorites();

  Stream<List<QuestionWithState>> watchWrongAnswers() =>
      _repository.watchWrongAnswers();

  Future<ProgressSummary> fetchProgress(String category, int year) {
    return _repository.fetchProgress(category, year);
  }

  Future<List<QuestionWithState>> searchQuestions(String query) {
    return _repository.searchQuestions(query);
  }

  Future<void> saveAnswer(Question question, int selectedIndex) {
    return _repository.saveAnswer(question, selectedIndex);
  }

  Future<void> toggleFavorite(Question question, bool isFavorite) {
    return _repository.toggleFavorite(question, isFavorite);
  }

  Future<void> dispose() => _repository.dispose();
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('AppDatabase must be overridden in main');
});

final questionRepositoryProvider = Provider<QuestionRepository>((ref) {
  return QuestionRepository(ref.watch(appDatabaseProvider));
});

final questionServiceProvider = Provider<QuestionService>((ref) {
  return QuestionService(ref.watch(questionRepositoryProvider));
});
