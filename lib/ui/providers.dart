import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/question_repository.dart';
import '../data/question_service.dart';

final seedProvider = FutureProvider<SeedRefreshResult>((ref) async {
  return ref.read(questionServiceProvider).ensureSeeded();
});

final categoriesProvider = StreamProvider((ref) {
  return ref.watch(questionServiceProvider).watchCategories();
});

final yearsProvider = StreamProvider.family((ref, String category) {
  return ref.watch(questionServiceProvider).watchYears(category);
});

final questionsProvider = StreamProvider.family((
  ref,
  ({String category, int year}) args,
) {
  return ref
      .watch(questionServiceProvider)
      .watchQuestions(args.category, args.year);
});

final favoritesProvider = StreamProvider((ref) {
  return ref.watch(questionServiceProvider).watchFavorites();
});

final wrongAnswersProvider = StreamProvider((ref) {
  return ref.watch(questionServiceProvider).watchWrongAnswers();
});

final progressProvider = StreamProvider.family((
  ref,
  ({String category, int year}) args,
) {
  return ref
      .watch(questionServiceProvider)
      .watchProgress(args.category, args.year);
});

final searchProvider = FutureProvider.family((ref, String query) {
  return ref.watch(questionServiceProvider).searchQuestions(query);
});
