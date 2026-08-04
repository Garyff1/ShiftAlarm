import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_mode_theme.dart';
import '../alarms/alarm_controller.dart';
import '../alarms/permission_center_page.dart';
import '../settings/interface_mode_page.dart';
import '../settings/settings_page.dart';
import '../shifts/shift_list_page.dart';
import '../sounds/sounds_page.dart';

class SimpleMorePage extends StatelessWidget {
  const SimpleMorePage({super.key});

  Future<void> _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Widget _pageBody(Widget child) =>
      Scaffold(body: SafeArea(bottom: false, child: child));

  @override
  Widget build(BuildContext context) {
    final alarms = context.watch<AlarmController>();
    final mode = AppModeTheme.of(context);
    return CustomScrollView(
      key: const PageStorageKey('simple-more-page'),
      slivers: [
        const SliverAppBar.large(title: Text('更多')),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            mode.pagePadding,
            0,
            mode.pagePadding,
            28,
          ),
          sliver: SliverList.list(
            children: [
              _MoreTile(
                icon: Icons.badge_rounded,
                title: '班次管理',
                subtitle: '新建和修改常用班次',
                onTap: () => _open(context, _pageBody(const ShiftListPage())),
              ),
              _MoreTile(
                icon: Icons.music_note_rounded,
                title: '铃声',
                subtitle: '试听和选择闹钟铃声',
                onTap: () => _open(context, _pageBody(const SoundsPage())),
              ),
              _MoreTile(
                icon:
                    alarms.permissions.ready &&
                        alarms.permissions.fullScreenIntent
                    ? Icons.verified_user_rounded
                    : Icons.warning_amber_rounded,
                title: '权限检查',
                subtitle:
                    alarms.permissions.ready &&
                        alarms.permissions.fullScreenIntent
                    ? '闹钟设置正常'
                    : '有一项需要处理',
                onTap: () => _open(
                  context,
                  const PermissionCenterPage(simpleMode: true),
                ),
              ),
              _MoreTile(
                icon: Icons.view_quilt_rounded,
                title: '界面模式',
                subtitle: '标准、大字或简易模式',
                onTap: () => _open(context, const InterfaceModePage()),
              ),
              _MoreTile(
                icon: Icons.settings_rounded,
                title: '设置',
                subtitle: '外观、时间和提醒默认值',
                onTap: () => _open(context, _pageBody(const SettingsPage())),
              ),
              _MoreTile(
                icon: Icons.info_rounded,
                title: '关于',
                subtitle: 'ShiftAlarm ${AppConstants.version}',
                onTap: () => showAboutDialog(
                  context: context,
                  applicationName: AppConstants.appName,
                  applicationVersion: AppConstants.version,
                  applicationLegalese: '排班、闹钟与适老化界面',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Semantics(
      button: true,
      label: '$title，$subtitle',
      child: Card(
        child: ListTile(
          contentPadding: EdgeInsets.all(
            AppModeTheme.of(context).cardPadding / 2,
          ),
          leading: Icon(icon, size: 32),
          title: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: onTap,
        ),
      ),
    ),
  );
}
