import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/question_repository.dart';
import '../../data/question_service.dart';
import '../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;
  List<_CategoryNode> _categoryTree = const [];

  @override
  Widget build(BuildContext context) {
    final seedState = ref.watch(seedProvider);
    final AsyncValue<List<CategorySummary>> categoriesAsync = ref.watch(
      categoriesProvider,
    );
    final isWide = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Question Bank'),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed('search'),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: () => context.pushNamed('library'),
            icon: const Icon(Icons.bookmark),
            tooltip: 'Favorites & Wrong',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'refresh') {
                _refreshQuestions();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'refresh',
                child: Text('Refresh questions from seed'),
              ),
            ],
          ),
        ],
      ),
      drawer: isWide
          ? null
          : Drawer(
              child: _buildCategoryList(categoriesAsync, onSelect: _onSelect),
            ),
      body: seedState.when(
        data: (_) {
          return categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) {
                return const Center(child: Text('No categories found.'));
              }
              _categoryTree = _buildTree(categories);
              _selectedCategory ??= _firstLeafPath(_categoryTree);
              final content = Row(
                children: [
                  if (isWide)
                    SizedBox(
                      width: 320,
                      child: _CategoryTree(
                        nodes: _categoryTree,
                        selected: _selectedCategory,
                        onSelect: _onSelect,
                      ),
                    ),
                  Expanded(child: _buildYearList(categories)),
                ],
              );
              return content;
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) =>
                Center(child: Text('Failed to load categories: $error')),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Failed to load seed data: $error')),
      ),
    );
  }

  Widget _buildCategoryList(
    AsyncValue<List<CategorySummary>> categoriesAsync, {
    required void Function(String) onSelect,
  }) {
    return categoriesAsync.when(
      data: (categories) {
        _categoryTree = _buildTree(categories);
        return ListView(
          children: [
            const DrawerHeader(
              child: Text('Categories', style: TextStyle(fontSize: 20)),
            ),
            _CategoryTree(
              nodes: _categoryTree,
              selected: _selectedCategory,
              onSelect: (path) {
                onSelect(path);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('Failed to load categories: $error')),
    );
  }

  Widget _buildYearList(List<CategorySummary> categories) {
    final selected = _selectedCategory ?? categories.first.category;
    final yearsAsync = ref.watch(yearsProvider(selected));
    return yearsAsync.when(
      data: (years) {
        if (years.isEmpty) {
          return const Center(
            child: Text('No questions found for this category.'),
          );
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              selected.toUpperCase(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final year in years)
                  Card(
                    child: ListTile(
                      title: Text('${year.year}'),
                      subtitle: Text('${year.count} questions'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.pushNamed(
                        'quiz',
                        pathParameters: {
                          'category': selected,
                          'year': '${year.year}',
                        },
                      ),
                    ),
                  ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          Center(child: Text('Failed to load years: $error')),
    );
  }

  void _onSelect(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  Future<void> _refreshQuestions() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final years =
          await ref.read(questionServiceProvider).refreshFromSeed();
      final label = years.isEmpty ? 'Updated question data' : 'Updated question data for years: ${years.join(', ')}';
      messenger.showSnackBar(
        SnackBar(content: Text(label)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Refresh failed: $e')),
      );
    }
  }
}

class _CategoryTree extends StatelessWidget {
  const _CategoryTree({
    required this.nodes,
    required this.selected,
    required this.onSelect,
  });

  final List<_CategoryNode> nodes;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: nodes.map((node) => _buildNode(context, node)).toList(),
    );
  }

  Widget _buildNode(BuildContext context, _CategoryNode node) {
    if (node.isLeaf) {
      return ListTile(
        title: Text(node.name),
        trailing: Text(node.count.toString()),
        selected: node.fullPath == selected,
        onTap: node.fullPath == null ? null : () => onSelect(node.fullPath!),
      );
    }
    return ExpansionTile(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(node.name)),
          Text(node.count.toString()),
        ],
      ),
      children: node.children.map((child) => _buildNode(context, child)).toList(),
    );
  }
}

class _CategoryNode {
  _CategoryNode(this.name);

  final String name;
  int count = 0;
  final List<_CategoryNode> children = [];
  String? fullPath;

  bool get isLeaf => children.isEmpty;
}

List<_CategoryNode> _buildTree(List<CategorySummary> categories) {
  final root = <_CategoryNode>[];

  _CategoryNode _findOrAdd(List<_CategoryNode> level, String name) {
    final existing = level.where((n) => n.name == name).toList();
    if (existing.isNotEmpty) return existing.first;
    final node = _CategoryNode(name);
    level.add(node);
    return node;
  }

  void insert(List<String> parts, int count) {
    var level = root;
    String path = '';
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      path = path.isEmpty ? part : '$path » $part';
      final node = _findOrAdd(level, part);
      node.count += count;
      if (i == parts.length - 1) {
        node.fullPath = path;
      }
      level = node.children;
    }
  }

  for (final cat in categories) {
    final parts = cat.category
        .split(RegExp(r'»|≫'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) continue;
    insert(parts, cat.count);
  }
  return root;
}

String? _firstLeafPath(List<_CategoryNode> nodes) {
  for (final n in nodes) {
    if (n.isLeaf) return n.fullPath;
    final child = _firstLeafPath(n.children);
    if (child != null) return child;
  }
  return null;
}
