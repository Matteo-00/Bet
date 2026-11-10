import 'dart:async';

import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../native.dart';
import '../parser.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'bet_editor.dart';
import 'bets_list.dart';
import 'dashboard.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int tab = 0;
  bool listenerEnabled = true;
  StreamSubscription? _shareSub;
  AppStore? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeNotifications.listen(() => _store?.syncNotifications());
    _shareSub = ReceiveSharingIntent.instance.getMediaStream().listen(_onShared, onError: (_) {});
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _onShared(files);
      ReceiveSharingIntent.instance.reset();
    }).catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkListener();
      _store?.syncNotifications();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppScope.read(context);
    if (_store != s) {
      _store?.removeListener(_onStore);
      _store = s..addListener(_onStore);
    }
  }

  void _onStore() {
    final s = _store;
    if (s == null || s.pendingToasts.isEmpty || !mounted) return;
    final msgs = List<String>.from(s.pendingToasts);
    s.pendingToasts.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) toast(context, msgs.join('\n'));
    });
  }

  void _onShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final img = files.firstWhere(
      (f) => f.type == SharedMediaType.image || RegExp(r'\.(png|jpe?g|webp)$', caseSensitive: false).hasMatch(f.path),
      orElse: () => files.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) startAddBet(context, sharedImage: img.path);
    });
  }

  Future<void> _checkListener() async {
    final e = await NativeNotifications.isEnabled();
    if (mounted && e != listenerEnabled) setState(() => listenerEnabled = e);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkListener();
      _store?.syncNotifications();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _store?.removeListener(_onStore);
    super.dispose();
  }

  static const _titles = ['Bet Tracker', 'Schedine', 'Statistiche', 'Impostazioni'];

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    if (!store.loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!store.settings.onboarded) return const OnboardingScreen();

    final pages = [
      DashboardScreen(
        onOpenStats: () => setState(() => tab = 2),
        onOpenBets: () => setState(() => tab = 1),
        listenerEnabled: listenerEnabled,
        onCheckListener: _checkListener,
      ),
      const BetsListScreen(),
      const StatsScreen(),
      SettingsScreen(listenerEnabled: listenerEnabled, onCheckListener: _checkListener),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[tab]),
        actions: [
          if (tab == 0 && store.openNotices.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Badge(
                label: Text('${store.openNotices.length}'),
                child: const Icon(Icons.notifications_rounded),
              ),
            ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(tab), child: pages[tab]),
      ),
      floatingActionButton: tab == 3
          ? null
          : FloatingActionButton.extended(
              onPressed: () => startAddBet(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Schedina', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard_rounded), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long_rounded), label: 'Schedine'),
          NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights_rounded), label: 'Statistiche'),
          NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune_rounded), label: 'Impostazioni'),
        ],
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final budget = TextEditingController();
  final limit = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final store = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Responsive(
          maxWidth: 520,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [C.primary, Color(0xFF1FA971)]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.insights_rounded, size: 34, color: Color(0xFF04140C)),
              ),
              const SizedBox(height: 22),
              const Text('Bet Tracker',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1)),
              const SizedBox(height: 8),
              const Text(
                'Tieni traccia di ogni schedina e scopri se stai andando meglio o peggio, '
                'settimana dopo settimana.',
                style: TextStyle(color: C.muted, fontSize: 15.5, height: 1.4),
              ),
              const SizedBox(height: 28),
              const _Feature(icon: Icons.ios_share_rounded, text: 'Screenshot da Eplay → Condividi → Bet Tracker: importo, quota ed eventi li leggo io.'),
              const _Feature(icon: Icons.notifications_active_rounded, text: 'Quando Eplay ti notifica una vincita, la schedina si segna vinta da sola.'),
              const _Feature(icon: Icons.insights_rounded, text: 'Saldo, rendimento, % vinte e confronto con la settimana o il mese prima.'),
              const SizedBox(height: 24),
              TextField(
                controller: budget,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Budget di partenza', suffixText: '€'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: limit,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Limite giornaliero (facoltativo)', suffixText: '€'),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () async {
                  final b = parseNumber(budget.text);
                  if (b == null || b <= 0) {
                    toast(context, 'Inserisci il budget di partenza');
                    return;
                  }
                  await store.updateSettings((s) {
                    s.startingBankroll = b;
                    s.dailyLimit = parseNumber(limit.text) ?? 0;
                    s.startDate = DateTime.now();
                    s.onboarded = true;
                  });
                },
                child: const Text('Inizia'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Feature({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: C.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 19, color: C.primary),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
        ]),
      );
}
