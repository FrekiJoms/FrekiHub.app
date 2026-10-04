part of 'design.dart';

class PermissionHintSpec {
  final String title, intro, benefit, detail, control, next, action;
  final IconData icon;
  const PermissionHintSpec({
    required this.title,
    required this.intro,
    required this.benefit,
    required this.detail,
    required this.control,
    required this.next,
    required this.action,
    required this.icon,
  });
}

/// One custom hint and gate for every app-owned Android permission request.
abstract final class PermissionHints {
  static bool _busy = false;
  static const specs = <String, PermissionHintSpec>{
    'start': PermissionHintSpec(
      title: 'Keep your session in view',
      intro: 'Follow your timer outside FrekiHub.',
      benefit: 'A quiet running timer',
      detail: 'Notifications and supported Dynamic Island displays show elapsed time and Clock out controls.',
      control: 'Your session stays saved even if you decline notifications. You can still end it from Home.',
      next: 'Allow FrekiHub notifications on the next screen.',
      action: 'Allow notifications',
      icon: LucideIcons.timer,
    ),
    'receiptNotificationPermission': PermissionHintSpec(
      title: 'Know when a transaction is saved',
      intro: 'Get a receipt after Finance saves your transaction.',
      benefit: 'A clear confirmation',
      detail: 'See the amount and merchant, and tap the notification to open Finance.',
      control: 'Declining notifications does not stop transactions from being saved. You can manage notification sounds in Settings.',
      next: 'Allow FrekiHub notifications in the Android prompt or settings.',
      action: 'Allow notifications',
      icon: LucideIcons.receipt,
    ),
    'reminderPermission': PermissionHintSpec(
      title: 'Let your reminders reach you',
      intro: 'Show the reminders you choose in your rules.',
      benefit: 'Your reminder, on your phone',
      detail: 'Android notifications display the title and message from your enabled reminder rules.',
      control: 'Nothing is sent to a server. You can stop a rule or change notification sounds at any time.',
      next: 'Allow FrekiHub notifications on the next screen.',
      action: 'Allow notifications',
      icon: LucideIcons.bell,
    ),
    'locationPermission': PermissionHintSpec(
      title: 'Use your current place',
      intro: 'Pick an accurate place for your location conditions.',
      benefit: 'Precise place checks',
      detail: 'Precise location helps place your condition and check whether you are inside its radius.',
      control: 'Location features are opt-in. Viewing recorded places on Map does not start tracking.',
      next: 'Choose Precise location and allow access while using the app.',
      action: 'Allow precise location',
      icon: LucideIcons.mapPin,
    ),
    'backgroundPermission': PermissionHintSpec(
      title: 'Keep location rules working',
      intro: 'Check your enabled place conditions while FrekiHub is closed.',
      benefit: 'Conditions beyond the app',
      detail: 'Background location lets Android check the places used by your enabled location rules. Android may delay checks.',
      control: 'Only opt-in location features use this access. You can disable location conditions or revoke access later.',
      next: 'Open Permissions → Location and choose Allow all the time. Precise location is also required.',
      action: 'Open location settings',
      icon: LucideIcons.mapPin,
    ),
    'notificationPermission': PermissionHintSpec(
      title: 'Detect purchases from your apps',
      intro: 'Turn selected payment alerts into queued purchases.',
      benefit: 'Use your selected payment apps',
      detail: 'Android grants notification access. FrekiHub filters purchase alerts from the payment apps you select.',
      control: 'OTPs and unrelated notification text are not stored. Purchases are saved to Finance when FrekiHub imports them.',
      next: 'Select FrekiHub on the next screen and allow notification access.',
      action: 'Allow notification access',
      icon: LucideIcons.creditCard,
    ),
    'exactReminderPermission': PermissionHintSpec(
      title: 'Give reminders precise timing',
      intro: 'Schedule your reminders at their chosen clock time.',
      benefit: 'Precise alarm scheduling',
      detail: 'Alarms & reminders access lets Android schedule precise alarms for your enabled reminders.',
      control: 'Without this access, reminders use less precise scheduling. Android and device settings can still affect delivery.',
      next: 'Enable Alarms & reminders for FrekiHub on the next screen.',
      action: 'Allow precise reminders',
      icon: LucideIcons.clock,
    ),
    'overlayPermission': PermissionHintSpec(
      title: 'Confirm wherever you are',
      intro: 'A final check, without leaving your current app.',
      benefit: 'Review before ending',
      detail: 'Clock out opens a confirmation and an editable session note over your current app.',
      control: 'It appears only when you tap Clock out. Your timer keeps running until you confirm.',
      next: 'Enable Display over other apps for FrekiHub on the next screen.',
      action: 'Allow overlay',
      icon: LucideIcons.layers,
    ),
  };

  static Future<T?> request<T>(
    BuildContext context,
    String method, {
    bool manage = false,
    PermissionHintSpec? hint,
  }) => perform<T>(
    context,
    method,
    () => manage
        ? NativeSession.channel.invokeMethod<T>('permissionSettings', method)
        : NativeSession.channel.invokeMethod<T>(method),
    manage: manage,
    hint: hint,
  );

  static Future<T?> perform<T>(
    BuildContext context,
    String method,
    Future<T?> Function() action, {
    bool manage = false,
    PermissionHintSpec? hint,
  }) async {
    final spec = specs[method];
    if (spec == null) {
      throw ArgumentError.value(method, 'method', 'Unknown permission');
    }
    if (_busy) return null;
    _busy = true;
    try {
      final status = await NativeSession.channel
          .invokeMapMethod<String, dynamic>('permissionStatus');
      if (!context.mounted) return null;
      final allowed = status?[method] == true;
      if (!allowed || manage) {
        final accepted = await panel<bool>(
          context,
          PermissionHint(spec: hint ?? spec, allowed: allowed),
        );
        if (accepted != true || !context.mounted) return null;
      }
      return await action();
    } finally {
      _busy = false;
    }
  }
}

class PermissionHint extends StatelessWidget {
  final PermissionHintSpec spec;
  final bool allowed;
  const PermissionHint({super.key, required this.spec, this.allowed = false});
  @override
  Widget build(BuildContext context) => PanelContent(
    header: PanelHeading(
      title: spec.title,
      leading: Chrome(
        padding: const EdgeInsets.all(10),
        child: Icon(spec.icon, size: 20),
      ),
    ),
    footer: PanelActions(
      children: [
        AppButton(
          label: allowed ? 'Manage access' : spec.action,
          onPressed: () => Navigator.pop(context, true),
        ),
        AppButton(
          label: 'Not now',
          secondary: true,
          onPressed: () => Navigator.pop(context, false),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          allowed ? 'Access is already enabled.' : spec.intro,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(spec.icon),
          title: Text(spec.benefit),
          subtitle: Text(spec.detail),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(LucideIcons.shieldCheck),
          title: const Text('You stay in control'),
          subtitle: Text(spec.control),
        ),
        const SizedBox(height: 12),
        Text(
          allowed
              ? 'On the next screen, manage this access for FrekiHub.'
              : spec.next,
          style: TextStyle(
            fontSize: 12,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

/// Compatibility wrapper; overlay hints use the same universal renderer.
class OverlayPermissionHint extends StatelessWidget {
  final bool allowed;
  const OverlayPermissionHint({super.key, required this.allowed});
  @override
  Widget build(BuildContext context) => PermissionHint(
    spec: PermissionHints.specs['overlayPermission']!,
    allowed: allowed,
  );
}
