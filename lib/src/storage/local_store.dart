import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();

  static const consignorsBox = 'consignors';
  static const contractsBox = 'contracts';
  static const settingsBox = 'settings';
  static const wizardDraftsBox = 'wizard_drafts';
  static const activityBox = 'activity';

  static Future<Directory> appDirectory() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();

    final directory = Directory(
      '${documentsDirectory.path}${Platform.pathSeparator}Consignor App',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static Future<Directory> contractsDirectory() async {
    final root = await appDirectory();

    final directory = Directory(
      '${root.path}${Platform.pathSeparator}Contracts',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static Future<Directory> idPicturesDirectory() async {
    final root = await appDirectory();

    final directory = Directory(
      '${root.path}${Platform.pathSeparator}Pictures${Platform.pathSeparator}ID',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  static Future<Directory> productPicturesDirectory() async {
    final root = await appDirectory();

    final directory = Directory(
      '${root.path}${Platform.pathSeparator}Pictures${Platform.pathSeparator}Products',
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return directory;
  }

  Future<void> initialize() async {
    final directory = await appDirectory();

    Hive.init(directory.path);

    await Hive.openBox(consignorsBox);
    await Hive.openBox(contractsBox);
    await Hive.openBox(settingsBox);
    await Hive.openBox(wizardDraftsBox);
    await Hive.openBox(activityBox);

    debugPrint('Hive storage path: ${directory.path}');
  }

  Box getBox(String name) => Hive.box(name);
}
