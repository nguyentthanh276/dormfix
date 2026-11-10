import 'package:flutter/material.dart';

/// One visible, labelled navigation pattern for all three roles.
class RoleNavigationBar extends StatelessWidget {
  const RoleNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) => NavigationBar(
    key: const Key('role-bottom-navigation'),
    selectedIndex: selectedIndex,
    onDestinationSelected: (index) {
      FocusManager.instance.primaryFocus?.unfocus();
      onDestinationSelected(index);
    },
    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    destinations: destinations,
  );
}
