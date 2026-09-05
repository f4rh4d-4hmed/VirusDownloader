import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../core/enums.dart';
import 'views/home_page.dart';
import 'views/settings_page.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _selectedIndex = 0;

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return const HomePage();
      case 1:
        return const HomePage(initialStatusFilter: DownloadStatus.downloading);
      case 2:
        return const SettingsPage();
      default:
        return const HomePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= AppConstants.compactWidth;
        final isExtended = constraints.maxWidth >= AppConstants.mediumWidth;

        if (isDesktop) {
          // Desktop / Tablet Layout with NavigationRail
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  extended: isExtended,
                  minWidth: 72,
                  minExtendedWidth: 200,
                  leading: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 12.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.download_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        if (isExtended) ...[
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              AppConstants.appName,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.all_inbox_outlined),
                      selectedIcon: Icon(Icons.all_inbox_rounded),
                      label: Text('Downloads'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.arrow_circle_down_outlined),
                      selectedIcon: Icon(Icons.arrow_circle_down_rounded),
                      label: Text('Active'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings_rounded),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: _buildBody()),
              ],
            ),
          );
        } else {
          // Mobile Layout with Bottom NavigationBar
          return Scaffold(
            body: _buildBody(),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedIndex = index;
                });
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.all_inbox_outlined),
                  selectedIcon: Icon(Icons.all_inbox_rounded),
                  label: 'Downloads',
                ),
                NavigationDestination(
                  icon: Icon(Icons.arrow_circle_down_outlined),
                  selectedIcon: Icon(Icons.arrow_circle_down_rounded),
                  label: 'Active',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          );
        }
      },
    );
  }
}

