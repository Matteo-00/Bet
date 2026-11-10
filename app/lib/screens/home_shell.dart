import 'package:flutter/material.dart';

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
  AppStore? _store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeNotifications.listen(
      onNotification: () => _store?.syncNotifications(),
      onReload: () => _store?.reload(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkListener());
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

  Future<void> _checkListener() async {
    final e = await NativeNotifications.isEnabled();
    if (mounted && e != listenerEnabled) setState(() => listenerEnabled = e);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkListener();
      _store?.reload().then((_) => _store?.syncNotifications());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
          _SyncIcon(store: store),
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
  bool includeOld = true;

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
              const _Feature(icon: Icons.ios_share_rounded, text: 'Screenshot da Eplay → Condividi → Bet Tracker: la schedina si registra da sola, senza aprire l\'app.'),
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
              if (store.bets.isNotEmpty) ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeOld,
                  onChanged: (v) => setState(() => includeOld = v),
                  title: Text('Conta le ${store.bets.length} schedine "Tu" già nel database'),
                  subtitle: Text('Il budget parte dal ${dateShort(_earliest(store))}; altrimenti da oggi.'),
                ),
              ],
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
                    s.startDate = includeOld && store.bets.isNotEmpty ? _earliest(store) : DateTime.now();
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

DateTime _earliest(AppStore s) {
  var d = DateTime.now();
  for (final b in s.bets) {
    if (b.placedAt.isBefore(d)) d = b.placedAt;
  }
  return DateTime(d.year, d.month, d.day);
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

class _SyncIcon extends StatelessWidget {
  final AppStore store;
  const _SyncIcon({required this.store});
  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String tip) = switch (store.syncState) {
      SyncState.syncing => (Icons.cloud_sync_rounded, C.muted, 'Sincronizzo…'),
      SyncState.offline => (Icons.cloud_off_rounded, C.pending, 'Offline: ${store.pendingOps} modifiche in attesa'),
      SyncState.error => (Icons.error_outline_rounded, C.loss, store.lastError ?? 'Errore database'),
      SyncState.idle => (store.pendingOps > 0 ? Icons.cloud_upload_rounded : Icons.cloud_done_rounded,
          store.pendingOps > 0 ? C.pending : C.primary, 'Sincronizzato con il database'),
    };
    return IconButton(
      tooltip: tip,
      icon: Icon(icon, color: color, size: 22),
      onPressed: () async {
        toast(context, tip);
        await store.sync();
      },
    );
  }
}
