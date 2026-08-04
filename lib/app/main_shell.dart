import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../features/home/home_page.dart';
import '../features/schedule/schedule_page.dart';
import '../features/settings/settings_page.dart';
import '../features/shifts/shift_list_page.dart';
import '../features/sounds/sounds_page.dart';
import '../features/sounds/sound_controller.dart';
import '../features/settings/app_controller.dart';
import '../features/simple/simple_home_page.dart';
import '../features/simple/simple_more_page.dart';
import '../features/simple/simple_schedule_page.dart';
import 'app_navigation.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const standardPages = [
    HomePage(),
    SchedulePage(),
    ShiftListPage(),
    SoundsPage(),
    SettingsPage(),
  ];

  static const simplePages = [
    SimpleHomePage(),
    SimpleSchedulePage(),
    SimpleMorePage(),
  ];

  @override
  Widget build(BuildContext context) {
    final navigation = context.watch<AppNavigationController>();
    final simple = context
        .watch<AppController>()
        .settings
        .interfaceMode
        .usesSimpleNavigation;
    final pages = simple ? simplePages : standardPages;
    final selectedIndex = navigation.index < pages.length
        ? navigation.index
        : 0;
    if (selectedIndex != navigation.index) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => navigation.ensureWithin(pages.length - 1),
      );
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: selectedIndex, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (!simple && navigation.index == 3 && index != 3) {
            unawaited(context.read<SoundController>().stopPreview());
          }
          navigation.select(index);
        },
        destinations: simple
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.today_outlined),
                  selectedIcon: Icon(Icons.today_rounded),
                  label: '今天',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: '排班',
                ),
                NavigationDestination(
                  icon: Icon(Icons.apps_outlined),
                  selectedIcon: Icon(Icons.apps_rounded),
                  label: '更多',
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: '首页',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: '排班',
                ),
                NavigationDestination(
                  icon: Icon(Icons.badge_outlined),
                  selectedIcon: Icon(Icons.badge_rounded),
                  label: '班次',
                ),
                NavigationDestination(
                  icon: Icon(Icons.music_note_outlined),
                  selectedIcon: Icon(Icons.music_note_rounded),
                  label: '铃声',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: '设置',
                ),
              ],
      ),
    );
  }
}
