import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/question.dart';
import '../providers.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = _query.isEmpty
        ? null
        : ref.watch(searchProvider(_query));

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Search questions',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _submitQuery,
                ),
              ),
              onSubmitted: (_) => _submitQuery(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: resultsAsync == null
                  ? const Center(
                      child: Text('Enter a keyword to search questions.'),
                    )
                  : resultsAsync.when(
                      data: (results) {
                        if (results.isEmpty) {
                          return const Center(child: Text('No matches found.'));
                        }
                        return ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index];
                            return Card(
                              child: ExpansionTile(
                                title: Text(item.question.text),
                                subtitle: Text(
                                  '${item.question.category} • ${item.question.year}',
                                ),
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final choice
                                            in item.question.choices)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            child: Text('• $choice'),
                                          ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Answer: ${_answerText(item.question)}',
                                        ),
                                        const SizedBox(height: 4),
                                        Text(item.question.explanation),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stack) =>
                          Center(child: Text('Search failed: $error')),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _submitQuery() {
    setState(() {
      _query = _controller.text.trim();
    });
  }

  String _answerText(Question question) {
    final index = question.answerIndex;
    if (index < 0 || index >= question.choices.length) {
      return 'Unavailable';
    }
    return question.choices[index];
  }
}
