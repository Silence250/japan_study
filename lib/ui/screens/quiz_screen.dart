import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/question_repository.dart';
import '../../data/question_service.dart';
import '../../models/question.dart';
import '../providers.dart';

class QuizScreen extends ConsumerStatefulWidget {
  const QuizScreen({super.key, required this.category, required this.year});

  final String category;
  final int year;

  @override
  ConsumerState<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends ConsumerState<QuizScreen> {
  int _index = 0;
  int? _selectedIndex;
  bool _checked = false;
  String? _currentQuestionId;

  @override
  Widget build(BuildContext context) {
    final questionsAsync = ref.watch(
      questionsProvider((category: widget.category, year: widget.year)),
    );
    final AsyncValue<ProgressSummary> progressAsync = ref.watch(
      progressProvider((category: widget.category, year: widget.year)),
    );

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBack,
          ),
          title: Text('${widget.category} ${widget.year}'),
          actions: [
            IconButton(
              icon: const Icon(Icons.home),
              tooltip: 'Home',
              onPressed: _handleHome,
            ),
          ],
        ),
        body: questionsAsync.when(
          data: (questions) {
            if (questions.isEmpty) {
              return const Center(child: Text('No questions found.'));
            }
            _index = _index.clamp(0, questions.length - 1);
            final item = questions[_index];
            _syncWithQuestion(item);

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ProgressHeader(
                    index: _index + 1,
                    total: questions.length,
                    progressAsync: progressAsync,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    item.question.text,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  _ChoicesList(
                    question: item.question,
                    selectedIndex: _selectedIndex,
                    checked: _checked,
                    onSelect: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: _selectedIndex == null
                            ? null
                            : () async {
                                await ref
                                    .read(questionServiceProvider)
                                    .saveAnswer(
                                      item.question,
                                      _selectedIndex!,
                                    );
                                setState(() {
                                  _checked = true;
                                });
                              },
                        child: Text(_checked ? 'Answered' : 'Check answer'),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: Icon(
                          item.answerState.isFavorite
                              ? Icons.star
                              : Icons.star_border,
                        ),
                        tooltip: 'Favorite',
                        onPressed: () async {
                          await ref
                              .read(questionServiceProvider)
                              .toggleFavorite(
                                item.question,
                                !item.answerState.isFavorite,
                              );
                        },
                      ),
                    ],
                  ),
                  if (_checked)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _ExplanationPanel(question: item.question),
                    ),
                  const Spacer(),
                  _NavigationBar(
                    hasPrevious: _index > 0,
                    hasNext: _index < questions.length - 1,
                    onPrevious: () => setState(() => _index -= 1),
                    onNext: () => setState(() => _index += 1),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stack) =>
              Center(child: Text('Failed to load questions: $error')),
        ),
      ),
    );
  }

  void _syncWithQuestion(QuestionWithState item) {
    if (_currentQuestionId == item.question.id) {
      if (!_checked && item.answerState.selectedIndex != null) {
        _selectedIndex = item.answerState.selectedIndex;
        _checked = true;
      }
      return;
    }
    _currentQuestionId = item.question.id;
    final hasAnswer = item.answerState.selectedIndex != null;
    if (hasAnswer) {
      _selectedIndex = item.answerState.selectedIndex;
      _checked = true;
    } else {
      _selectedIndex = null;
      _checked = false;
    }
  }

  Future<bool> _onWillPop() async {
    return _confirmLeave();
  }

  Future<void> _handleBack() async {
    if (await _confirmLeave()) {
      if (context.canPop()) {
        context.pop();
      } else {
        // Fallback to home if no back stack exists.
        context.goNamed('home');
      }
    }
  }

  Future<void> _handleHome() async {
    if (await _confirmLeave()) {
      if (mounted) {
        context.goNamed('home');
      }
    }
  }

  Future<bool> _confirmLeave() async {
    if (!_hasProgress) {
      return true;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave quiz?'),
        content: const Text('Your progress may be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  bool get _hasProgress =>
      _checked || _selectedIndex != null || _index > 0;
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({
    required this.index,
    required this.total,
    required this.progressAsync,
  });

  final int index;
  final int total;
  final AsyncValue<ProgressSummary> progressAsync;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Question $index / $total'),
        progressAsync.when(
          data: (progress) => Text(
            'Answered ${progress.answered} • Correct ${progress.correct}',
          ),
          loading: () => const Text('Loading progress...'),
          error: (error, stack) => const Text('Progress unavailable'),
        ),
      ],
    );
  }
}

class _ChoicesList extends StatelessWidget {
  const _ChoicesList({
    required this.question,
    required this.selectedIndex,
    required this.checked,
    required this.onSelect,
  });

  final Question question;
  final int? selectedIndex;
  final bool checked;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < question.choices.length; i++)
          Card(
            color: _choiceColor(i),
            child: ListTile(
              title: Text(question.choices[i]),
              leading: Radio<int>(
                value: i,
                groupValue: selectedIndex,
                onChanged: checked ? null : (value) => onSelect(value!),
              ),
              onTap: checked ? null : () => onSelect(i),
            ),
          ),
      ],
    );
  }

  Color? _choiceColor(int index) {
    if (!checked) {
      return null;
    }
    if (index == question.answerIndex) {
      return Colors.green.withOpacity(0.2);
    }
    if (index == selectedIndex && selectedIndex != question.answerIndex) {
      return Colors.red.withOpacity(0.2);
    }
    return null;
  }
}

class _ExplanationPanel extends StatelessWidget {
  const _ExplanationPanel({required this.question});

  final Question question;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Explanation', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(question.explanation),
          ],
        ),
      ),
    );
  }
}

class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
  });

  final bool hasPrevious;
  final bool hasNext;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        OutlinedButton.icon(
          onPressed: hasPrevious ? onPrevious : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Prev'),
        ),
        OutlinedButton.icon(
          onPressed: hasNext ? onNext : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Next'),
        ),
      ],
    );
  }
}
