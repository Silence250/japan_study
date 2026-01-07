import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/question_repository.dart';
import '../providers.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Library'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Favorites'),
              Tab(text: 'Wrong Answers'),
            ],
          ),
        ),
        body: const TabBarView(children: [_FavoritesTab(), _WrongAnswersTab()]),
      ),
    );
  }
}

class _FavoritesTab extends ConsumerWidget {
  const _FavoritesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);
    return favoritesAsync.when(
      data: (items) =>
          _QuestionList(items: items, emptyLabel: 'No favorites yet.'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('Failed to load favorites: $error')),
    );
  }
}

class _WrongAnswersTab extends ConsumerWidget {
  const _WrongAnswersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wrongAsync = ref.watch(wrongAnswersProvider);
    return wrongAsync.when(
      data: (items) =>
          _QuestionList(items: items, emptyLabel: 'No wrong answers yet.'),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('Failed to load wrong answers: $error')),
    );
  }
}

class _QuestionList extends StatelessWidget {
  const _QuestionList({required this.items, required this.emptyLabel});

  final List<QuestionWithState> items;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(child: Text(emptyLabel));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          child: ListTile(
            title: Text(item.question.text),
            subtitle: Text('${item.question.category} • ${item.question.year}'),
          ),
        );
      },
    );
  }
}
