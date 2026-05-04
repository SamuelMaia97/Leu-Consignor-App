import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/app_lock_service.dart';
import '../state/app_state.dart';
import '../widgets/app_shell.dart';
import '../widgets/page_header.dart';
import '../widgets/section_card.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _service = AppLockService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  List<String> _usernames = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final usernames = await _service.listUsernames();
    if (!mounted) return;
    setState(() {
      _usernames = usernames;
      _loading = false;
    });
  }

  Future<void> _saveUser() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      _showSnack('Username and password are required.');
      return;
    }
    await _service.upsertUser(username, password);
    _usernameController.clear();
    _passwordController.clear();
    await _loadUsers();
    _showSnack('User saved.');
  }

  Future<void> _removeUser(String username) async {
    if (username == AppLockService.defaultUsername) {
      _showSnack('The admin user cannot be removed.');
      return;
    }
    await _service.removeUser(username);
    await _loadUsers();
    _showSnack('User removed.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.watch<AppState>().isAdminUser;
    return AppShell(
      title: 'Users',
      child: !isAdmin
          ? const Center(child: Text('Only the admin user can manage app users.'))
          : ListView(
        children: [
          const PageHeader(
            eyebrow: 'ADMIN',
            title: 'Manage app users',
          ),
          const SizedBox(height: 24),
          SectionCard(
            title: 'Add or update user',
            icon: Icons.person_add_alt_1_outlined,
            child: Column(
              children: [
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saveUser,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('Save user'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SectionCard(
            title: 'Existing users',
            icon: Icons.people_outline,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      for (final username in _usernames)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(username),
                          trailing: IconButton(
                            tooltip: 'Remove user',
                            onPressed: username == AppLockService.defaultUsername
                                ? null
                                : () => _removeUser(username),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
