import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'screens/search_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Streaming Manage App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
      ),
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  int _currentIndex = 0;

  // IndexedStack で状態を保持（タブ切り替え時にスクロール位置などが消えない）
  static const _screens = [
    HomeScreen(),
    SearchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'カレンダー',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: '検索',
          ),
        ],
      ),
    );
  }
}