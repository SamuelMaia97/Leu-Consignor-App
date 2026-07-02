import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'leu_logo.dart';
import 'responsive.dart';
import 'status_badge.dart';

bool _desktopSidebarCollapsed = false;

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late bool _sidebarCollapsed;

  @override
  void initState() {
    super.initState();
    _sidebarCollapsed = _desktopSidebarCollapsed;
  }

  void _toggleSidebarCollapsed() {
    setState(() {
      _sidebarCollapsed = !_sidebarCollapsed;
      _desktopSidebarCollapsed = _sidebarCollapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    final selectedIndex = _selectedIndex(location);
    final desktop = isDesktopWidth(context);
    final palette = context.palette;

    final animatedPage = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offsetAnimation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey(location),
        child: widget.child,
      ),
    );

    return Scaffold(
      backgroundColor: palette.surface,
      drawer: desktop
          ? null
          : Drawer(
              backgroundColor: Colors.transparent,
              elevation: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _Sidebar(
                    selectedIndex: selectedIndex,
                    collapsed: false,
                    onSelect: (index) {
                      Navigator.of(context).pop();
                      _go(context, index);
                    },
                  ),
                ),
              ),
            ),
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              palette.surface,
              Colors.white,
              palette.brandSoft.withValues(alpha: 0.8),
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -180,
              right: -120,
              child: _AmbientOrb(
                size: 360,
                color: palette.brandAccent.withValues(alpha: 0.10),
              ),
            ),
            Positioned(
              bottom: -220,
              left: desktop ? 180 : -120,
              child: _AmbientOrb(
                size: 420,
                color: palette.brand.withValues(alpha: 0.08),
              ),
            ),
            SafeArea(
              child: Row(
                children: [
                  if (desktop) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 0, 18),
                      child: _Sidebar(
                        selectedIndex: selectedIndex,
                        collapsed: _sidebarCollapsed,
                        onToggleCollapsed: _toggleSidebarCollapsed,
                        onSelect: (index) => _go(context, index),
                      ),
                    ),
                    const SizedBox(width: 18),
                  ],
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 0 : 14,
                        14,
                        14,
                        14,
                      ),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.74),
                          borderRadius: BorderRadius.circular(34),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  palette.brandStrong.withValues(alpha: 0.06),
                              blurRadius: 34,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            _TopBar(
                              title: widget.title,
                              showMenu: !desktop,
                            ),
                            Consumer<AppState>(
                              builder: (context, state, _) {
                                if (!state.syncingNow &&
                                    !state.syncingAllDrafts) {
                                  return const SizedBox.shrink();
                                }

                                return Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    desktop ? 28 : 16,
                                    0,
                                    desktop ? 28 : 16,
                                    16,
                                  ),
                                  child: _ShellSyncProgress(state: state),
                                );
                              },
                            ),
                            Expanded(
                              child: ResponsiveContent(
                                maxWidth: 1540,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    desktop ? 28 : 16,
                                    0,
                                    desktop ? 28 : 16,
                                    desktop ? 28 : 16,
                                  ),
                                  child: animatedPage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _go(BuildContext context, int index) async {
    final targetLocation = switch (index) {
      0 => '/',
      1 => '/consignors',
      2 => '/contracts',
      3 => '/sync-health',
      4 => '/settings',
      5 => '/users',
      _ => '/',
    };

    final currentLocation = GoRouterState.of(context).uri.toString();
    if (currentLocation == targetLocation) return;

    final canLeave =
        await context.read<AppState>().canLeaveCurrentRoute(consume: true);

    if (!context.mounted || !canLeave) return;

    context.go(targetLocation);
  }

  int _selectedIndex(String location) {
    if (location.startsWith('/consignors')) return 1;
    if (location.startsWith('/contracts')) return 2;
    if (location.startsWith('/sync-health')) return 3;
    if (location.startsWith('/settings')) return 4;
    if (location.startsWith('/users')) return 5;
    return 0;
  }
}

class _ShellSyncProgress extends StatelessWidget {
  const _ShellSyncProgress({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final message = state.syncingNow
        ? (state.syncProgressMessage.trim().isEmpty
            ? 'Syncing workspace…'
            : state.syncProgressMessage.trim())
        : 'Syncing pending drafts…';

    final hasKnownTotal = state.syncingNow && state.syncProgressTotal > 0;
    final progressValue = hasKnownTotal ? state.syncProgressValue : null;

    final current =
        state.syncProgressCurrent < 0 ? 0 : state.syncProgressCurrent;
    final total = state.syncProgressTotal;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.brandSoft.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progressValue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: palette.brandStrong,
                      ),
                ),
              ),
              if (hasKnownTotal) ...[
                const SizedBox(width: 12),
                Text(
                  '$current of $total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.brand,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progressValue),
        ],
      ),
    );
  }
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, required this.showMenu});

  final String title;
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final now = DateTime.now();
    final month = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ][now.month];

    return Padding(
      padding: EdgeInsets.fromLTRB(showMenu ? 12 : 18, 18, 18, 14),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showMenu ? 12 : 18,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: palette.border.withValues(alpha: 0.78)),
        ),
        child: Row(
          children: [
            if (showMenu) ...[
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'Open navigation',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: const Icon(Icons.menu_rounded),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$month ${now.day}, ${now.year}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Consumer<AppState>(
              builder: (context, state, _) {
                final syncing = state.syncingNow || state.syncingAllDrafts;

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    if (!showMenu)
                      StatusBadge(
                        label: state.signingIn
                            ? 'Microsoft sign-in…'
                            : state.hasValidToken
                                ? 'Microsoft connected'
                                : 'Microsoft login needed',
                        tone: state.hasValidToken
                            ? StatusBadgeTone.success
                            : StatusBadgeTone.warning,
                        icon: state.hasValidToken
                            ? Icons.verified_user_outlined
                            : Icons.lock_outline_rounded,
                        onTap: state.signingIn
                            ? null
                            : () async {
                                if (state.hasValidToken) {
                                  context.go('/settings');
                                  return;
                                }

                                await state.signInWithMicrosoft();
                                if (!context.mounted ||
                                    state.lastMessage == null) {
                                  return;
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(state.lastMessage!)),
                                );
                              },
                      ),
                    StatusBadge(
                      label: syncing ? 'Syncing' : 'Workspace ready',
                      tone: syncing
                          ? StatusBadgeTone.info
                          : StatusBadgeTone.neutral,
                      icon: syncing
                          ? Icons.sync_rounded
                          : Icons.check_circle_outline_rounded,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.collapsed,
    this.onToggleCollapsed,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final state = context.watch<AppState>();
    final activeUsername = state.activeUsername ?? 'staff';
    final initials = _initials(activeUsername);

    final navItems = <Widget>[
      _NavItem(
        label: 'Dashboard',
        icon: Icons.grid_view_rounded,
        selected: selectedIndex == 0,
        collapsed: collapsed,
        onTap: () => onSelect(0),
      ),
      _NavItem(
        label: 'Consignors',
        icon: Icons.people_alt_outlined,
        selected: selectedIndex == 1,
        collapsed: collapsed,
        onTap: () => onSelect(1),
      ),
      _NavItem(
        label: 'Contracts',
        icon: Icons.description_outlined,
        selected: selectedIndex == 2,
        collapsed: collapsed,
        onTap: () => onSelect(2),
      ),
      _NavItem(
        label: 'Sync health',
        icon: Icons.monitor_heart_outlined,
        selected: selectedIndex == 3,
        collapsed: collapsed,
        onTap: () => onSelect(3),
      ),
      _NavItem(
        label: 'Settings',
        icon: Icons.settings_outlined,
        selected: selectedIndex == 4,
        collapsed: collapsed,
        onTap: () => onSelect(4),
      ),
      if (state.isAdminUser)
        _NavItem(
          label: 'Users',
          icon: Icons.manage_accounts_outlined,
          selected: selectedIndex == 5,
          collapsed: collapsed,
          onTap: () => onSelect(5),
        ),
    ];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: collapsed ? 88 : 286,
      padding: EdgeInsets.all(collapsed ? 12 : 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.brandStrong, palette.brand, palette.brandStrong],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: palette.brand.withValues(alpha: 0.20),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(
            collapsed: collapsed,
            onToggleCollapsed: onToggleCollapsed,
          ),
          const SizedBox(height: 26),
          if (!collapsed) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                'WORKSPACE',
                style: TextStyle(
                  color: Color(0xFFDCE6F3),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(children: navItems),
            ),
          ),
          const SizedBox(height: 12),
          _SidebarUserTile(
            collapsed: collapsed,
            initials: initials,
            activeUsername: activeUsername,
            onLogout: () => _logout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final appState = context.read<AppState>();
    final canLeave = await appState.canLeaveCurrentRoute(consume: true);

    if (!context.mounted || !canLeave) return;

    context.go('/');
    appState.logoutLocalUser();
  }

  String _initials(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'S';

    final parts = trimmed.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 10 : 18,
        vertical: collapsed ? 12 : 20,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: collapsed
                ? const LeuLogo(
                    key: ValueKey('collapsed-logo'),
                    size: 42,
                    variant: LeuLogoVariant.iconOnly,
                  )
                : const LeuLogo(
                    key: ValueKey('expanded-logo'),
                    size: 196,
                    variant: LeuLogoVariant.full,
                  ),
          ),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            const Text(
              'C.O.I.N.S.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFDCE6F3),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (onToggleCollapsed != null) ...[
            SizedBox(height: collapsed ? 10 : 14),
            Tooltip(
              message: collapsed ? 'Expand navigation' : 'Collapse navigation',
              child: IconButton(
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_double_arrow_right_rounded
                      : Icons.keyboard_double_arrow_left_rounded,
                ),
                color: Colors.white,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  hoverColor: Colors.white.withValues(alpha: 0.16),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SidebarUserTile extends StatelessWidget {
  const _SidebarUserTile({
    required this.collapsed,
    required this.initials,
    required this.activeUsername,
    required this.onLogout,
  });

  final bool collapsed;
  final String initials;
  final String activeUsername;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final avatar = CircleAvatar(
      radius: 18,
      backgroundColor: palette.brandAccent,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: collapsed
          ? Column(
              children: [
                Tooltip(message: activeUsername, child: avatar),
                const SizedBox(height: 8),
                Tooltip(
                  message: 'Log out',
                  child: IconButton(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      hoverColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        activeUsername,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'Signed in',
                        style: TextStyle(
                          color: Color(0xFFDCE6F3),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Log out',
                  child: IconButton(
                    onPressed: onLogout,
                    icon: const Icon(Icons.logout_rounded),
                    color: Colors.white,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      hoverColor: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    final item = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              mainAxisAlignment: collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  color: selected ? palette.brand : Colors.white,
                  size: 20,
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: selected ? palette.brand : Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: selected ? 1 : 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: palette.brand,
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return collapsed ? Tooltip(message: label, child: item) : item;
  }
}
