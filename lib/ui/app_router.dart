import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'screens/home_screen.dart';
import 'screens/library_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/search_screen.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: [
      GoRoute(
        name: 'home',
        path: '/',
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        name: 'quiz',
        path: '/quiz/:category/:year',
        builder: (context, state) {
          final category = state.pathParameters['category']!;
          final year = int.parse(state.pathParameters['year']!);
          return QuizScreen(category: category, year: year);
        },
      ),
      GoRoute(
        name: 'search',
        path: '/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        name: 'library',
        path: '/library',
        builder: (context, state) => const LibraryScreen(),
      ),
    ],
  );
});
