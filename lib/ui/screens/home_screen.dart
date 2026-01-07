import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/question_repository.dart';
import '../providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedCategory;

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
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search),
            tooltip: 'Search',
          ),
          IconButton(
            onPressed: () => context.go('/library'),
            icon: const Icon(Icons.bookmark),
            tooltip: 'Favorites & Wrong',
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
              _selectedCategory ??= categories.first.category;
              final content = Row(
                children: [
                  if (isWide)
                    NavigationRail(
                      selectedIndex: categories.indexWhere(
                        (cat) => cat.category == _selectedCategory,
                      ),
                      onDestinationSelected: (index) =>
                          _onSelect(categories[index].category),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final category in categories)
                          NavigationRailDestination(
                            icon: const Icon(Icons.folder),
                            label: Text(category.category),
                          ),
                      ],
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
        return ListView(
          children: [
            const DrawerHeader(
              child: Text('Categories', style: TextStyle(fontSize: 20)),
            ),
            for (final category in categories)
              ListTile(
                title: Text(category.category),
                trailing: Text(category.count.toString()),
                selected: category.category == _selectedCategory,
                onTap: () {
                  onSelect(category.category);
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
                  onTap: () => context.go('/quiz/$selected/${year.year}'),
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
}
