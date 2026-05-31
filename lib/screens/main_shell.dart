import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme.dart';
import '../providers/auth_provider.dart';
import '../services/database_service.dart';
import '../services/realtime_presence_service.dart';
import '../services/ctf_service.dart';
import '../services/fcm_service.dart';
import 'map_screen.dart';
import 'profile_screen.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initServices());
  }

  Future<void> _initServices() async {
    final userId = ref.read(authProvider).user?['id'] as String?;
    if (userId == null) return;
    final rows = await DatabaseService.instance.db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final profile = rows.first;
    RealtimePresenceService.instance.init(
      playerId: userId,
      displayName: (profile['username'] as String?) ?? 'RUNNER',
      color: (profile['color'] as String?) ?? '#FF7A00',
    );
    await CtfService.instance.init(playerId: userId);
    await FcmService.instance.init(playerId: userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      // AC-14: IndexedStack keeps both children mounted across tab switches
      // so MapScreen state and zonesProvider subscription survive switching.
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          MapScreen(),
          ProfileScreen(),
        ],
      ),
      // AC-12, AC-15: exactly two tabs; active = kAccent, inactive = kFgMuted.
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (i) => setState(() => _selectedIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: kBg,
        selectedItemColor: kAccent,
        unselectedItemColor: kFgMuted,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
