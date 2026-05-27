import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'screens/app_lock_screen.dart';
import 'screens/contract_editor_screen.dart';
import 'screens/contract_list_screen.dart';
import 'screens/contracts_overview_screen.dart';
import 'screens/consignor_editor_screen.dart';
import 'screens/consignor_list_screen.dart';
import 'screens/consignor_wizard_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/user_management_screen.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

class LeuApp extends StatefulWidget {
  const LeuApp({super.key});

  @override
  State<LeuApp> createState() => _LeuAppState();
}

class _LeuAppState extends State<LeuApp> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/',
    errorBuilder: (_, __) => const HomeScreen(),
    routes: [
      GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
      GoRoute(
          path: '/consignors', builder: (_, __) => const ConsignorListScreen()),
      GoRoute(
        path: '/consignors/new',
        builder: (_, __) => const ConsignorWizardScreen(),
      ),
      GoRoute(
        path: '/consignors/:id/resume',
        builder: (_, state) => ConsignorWizardScreen(
          resumeConsignorId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/consignors/:id',
        builder: (_, state) =>
            ConsignorEditorScreen(consignorId: state.pathParameters['id']),
      ),
      GoRoute(
          path: '/contracts', builder: (_, __) => const ContractListScreen()),
      GoRoute(
        path: '/contracts/new',
        builder: (_, __) => const ConsignorWizardScreen(contractOnly: true),
      ),
      GoRoute(
        path: '/contracts/:id',
        builder: (_, state) => ContractsOverviewScreen(
          consignorId: state.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/contracts/:id/new',
        builder: (_, state) => ConsignorWizardScreen(
          contractOnly: true,
          resumeConsignorId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: '/contracts/:id/:auctionId',
        builder: (_, state) => ContractEditorScreen(
          consignorId: state.pathParameters['id']!,
          auctionId: int.tryParse(state.pathParameters['auctionId'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/contracts/:id/record/:contractId/resume',
        builder: (_, state) => ConsignorWizardScreen(
          contractOnly: true,
          resumeConsignorId: state.pathParameters['id'],
          resumeContractId: state.pathParameters['contractId'],
        ),
      ),
      GoRoute(
        path: '/contracts/:id/record/:contractId',
        builder: (_, state) => ContractEditorScreen(
          consignorId: state.pathParameters['id']!,
          contractId: state.pathParameters['contractId'],
        ),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/users',
        builder: (context, _) => context.read<AppState>().isAdminUser
            ? const UserManagementScreen()
            : const SettingsScreen(),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final theme = buildAppTheme();
    final activeUsername = context.watch<AppState>().activeUsername;

    if (activeUsername == null || activeUsername.trim().isEmpty) {
      return MaterialApp(
        title: 'Leu Consignor App',
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: AppLockScreen(
          onUnlocked: (username) {
            context.read<AppState>().setActiveUsername(username);
          },
        ),
      );
    }

    return MaterialApp.router(
      title: 'Leu Consignor App',
      theme: theme,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
