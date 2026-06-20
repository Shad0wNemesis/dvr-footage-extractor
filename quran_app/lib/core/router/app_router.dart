import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/quran/screens/surah_list_screen.dart';
import '../../features/quran/screens/quran_reader_screen.dart';
import '../../features/quran/screens/search_screen.dart';
import '../../features/tafsir/screens/tafsir_screen.dart';
import '../../features/prayer/screens/prayer_times_screen.dart';
import '../../features/qibla/screens/qibla_screen.dart';
import '../../features/bookmarks/screens/bookmarks_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/splash/splash_screen.dart';
import '../../features/semantic_search/screens/semantic_search_screen.dart';
import '../../features/hifz/screens/hifz_screen.dart';
import '../../features/recitation_checker/screens/recitation_screen.dart';
import '../../features/ar_scanner/screens/ar_scanner_screen.dart';

class AppRoutes {
  static const splash = '/splash';
  static const home = '/';
  static const surahList = '/quran';
  static const reader = '/quran/:surahId';
  static const readerPage = '/quran/page/:pageNumber';
  static const search = '/search';
  static const semanticSearch = '/semantic-search';
  static const tafsir = '/tafsir/:verseKey';
  static const prayer = '/prayer';
  static const qibla = '/qibla';
  static const bookmarks = '/bookmarks';
  static const settings = '/settings';
  static const hifz = '/hifz';
  static const recitation = '/recitation/:verseKey';
  static const arScanner = '/scanner';
}

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  debugLogDiagnostics: false,
  routes: [
    // Splash is outside the ShellRoute — no bottom nav during init.
    GoRoute(
      path: AppRoutes.splash,
      pageBuilder: (context, state) => _buildPage(state, const SplashScreen()),
    ),

    // Full-screen routes (no bottom nav).
    GoRoute(
      path: AppRoutes.arScanner,
      pageBuilder: (context, state) => _buildPage(state, const ARScannerScreen()),
    ),
    GoRoute(
      path: AppRoutes.recitation,
      pageBuilder: (context, state) {
        final verseKey = Uri.decodeComponent(
            state.pathParameters['verseKey'] ?? '1:1');
        return _buildPage(state, RecitationScreen(verseKey: verseKey));
      },
    ),
    GoRoute(
      path: AppRoutes.semanticSearch,
      pageBuilder: (context, state) =>
          _buildPage(state, const SemanticSearchScreen()),
    ),
    GoRoute(
      path: AppRoutes.hifz,
      pageBuilder: (context, state) => _buildPage(state, const HifzScreen()),
    ),

    // Main shell with bottom nav.
    ShellRoute(
      builder: (context, state, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: AppRoutes.home,
          pageBuilder: (context, state) => _buildPage(state, const HomeScreen()),
        ),
        GoRoute(
          path: AppRoutes.surahList,
          pageBuilder: (context, state) => _buildPage(state, const SurahListScreen()),
        ),
        GoRoute(
          path: AppRoutes.reader,
          pageBuilder: (context, state) {
            final surahId = int.parse(state.pathParameters['surahId'] ?? '1');
            final verseNumber = int.tryParse(state.uri.queryParameters['verse'] ?? '');
            return _buildPage(
              state,
              QuranReaderScreen(surahId: surahId, initialVerse: verseNumber),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.readerPage,
          pageBuilder: (context, state) {
            final pageNumber = int.parse(state.pathParameters['pageNumber'] ?? '1');
            // Open surah 1 as a fallback; a full page→surah map is a future enhancement.
            return _buildPage(
              state,
              QuranReaderScreen(surahId: 1, initialVerse: pageNumber),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.search,
          pageBuilder: (context, state) => _buildPage(state, const SearchScreen()),
        ),
        GoRoute(
          path: AppRoutes.prayer,
          pageBuilder: (context, state) => _buildPage(state, const PrayerTimesScreen()),
        ),
        GoRoute(
          path: AppRoutes.qibla,
          pageBuilder: (context, state) => _buildPage(state, const QiblaScreen()),
        ),
        GoRoute(
          path: AppRoutes.bookmarks,
          pageBuilder: (context, state) => _buildPage(state, const BookmarksScreen()),
        ),
        GoRoute(
          path: AppRoutes.settings,
          pageBuilder: (context, state) => _buildPage(state, const SettingsScreen()),
        ),
        GoRoute(
          path: AppRoutes.tafsir,
          pageBuilder: (context, state) {
            final verseKey = state.pathParameters['verseKey'] ?? '1:1';
            return _buildPage(state, TafsirScreen(verseKey: verseKey));
          },
        ),
      ],
    ),
  ],
);

CustomTransitionPage<void> _buildPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 200),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});
  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  static const _navItems = [
    (icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', route: AppRoutes.home),
    (icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'Quran', route: AppRoutes.surahList),
    (icon: Icons.access_time_outlined, activeIcon: Icons.access_time, label: 'Prayer', route: AppRoutes.prayer),
    (icon: Icons.bookmark_outline, activeIcon: Icons.bookmark, label: 'Saved', route: AppRoutes.bookmarks),
    (icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings', route: AppRoutes.settings),
  ];

  void _onTabTapped(int index) {
    if (index != _selectedIndex) {
      setState(() => _selectedIndex = index);
      context.go(_navItems[index].route);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        items: _navItems.map((item) => BottomNavigationBarItem(
          icon: Icon(item.icon),
          activeIcon: Icon(item.activeIcon),
          label: item.label,
        )).toList(),
      ),
    );
  }
}
