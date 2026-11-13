import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<bool> saveJsonBackup(
  Map<String, Object?> data, {
  required String filenamePrefix,
}) async {
  final content = jsonEncode(data);
  if (utf8.encode(content).length > 100 * 1024 * 1024) {
    throw const FormatException('备份超过 100 MB');
  }
  final dir = await getTemporaryDirectory();
  final file = File(
    p.join(dir.path, 'backup_${DateTime.now().microsecondsSinceEpoch}.json'),
  );
  try {
    await file.writeAsString(content, flush: true);
    return await const MethodChannel(
          'noodles/data_transfer',
        ).invokeMethod<bool>('exportFile', {
          'path': file.path,
          'name':
              '${filenamePrefix}_${DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-')}.json',
        }) ??
        false;
  } finally {
    if (await file.exists()) await file.delete();
  }
}
