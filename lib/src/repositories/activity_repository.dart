import 'package:hive/hive.dart';

import '../models/activity_event.dart';
import '../storage/local_store.dart';

class ActivityRepository {
  static const int maxEvents = 200;

  Box? get _box => Hive.isBoxOpen(LocalStore.activityBox)
      ? LocalStore.instance.getBox(LocalStore.activityBox)
      : null;

  List<ActivityEvent> getAll() {
    final box = _box;
    if (box == null) return const [];

    final events = box.values
        .map((value) =>
            ActivityEvent.fromJson(Map<String, dynamic>.from(value as Map)))
        .toList()
      ..sort(
          (left, right) => right.occurredAtUtc.compareTo(left.occurredAtUtc));

    return events;
  }

  Future<void> add(ActivityEvent event) async {
    final box = _box;
    if (box == null) return;

    await box.put(event.id, event.toJson());
    await _trim();
  }

  Future<void> clear() async {
    final box = _box;
    if (box == null) return;
    await box.clear();
  }

  Future<void> _trim() async {
    final box = _box;
    if (box == null) return;

    final events = getAll();
    if (events.length <= maxEvents) return;

    for (final event in events.skip(maxEvents)) {
      await box.delete(event.id);
    }
  }
}
