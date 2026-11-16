import 'dart:io';

import 'package:easy_video_editor/easy_video_editor.dart';

final RegExp _unsafePathChars = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u0085\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);

bool _hasSymlinkAncestor(String rawPath) {
  var current = rawPath;
  final visited = <String>{};
  while (current.isNotEmpty && visited.add(current)) {
    if (current != '/tmp' &&
        current != '/var' &&
        current != '/etc' &&
        FileSystemEntity.isLinkSync(current)) {
      return true;
    }
    final parent = File(current).parent.path;
    if (parent == current) break;
    current = parent;
  }
  return false;
}

bool _isSafeFlipPath(String rawPath) {
  if (rawPath.isEmpty || rawPath.length > 1024) return false;
  final trimmed = rawPath.trim();
  if (trimmed != rawPath || trimmed.startsWith('-')) return false;
  if (_unsafePathChars.hasMatch(trimmed)) return false;
  if (trimmed.startsWith('//') ||
      trimmed.startsWith(r'\\') ||
      trimmed.startsWith(r'\??\')) {
    return false;
  }
  final segments = trimmed.split(RegExp(r'[/\\]+'));
  if (segments.any((s) => s == '..')) return false;
  return !_hasSymlinkAncestor(trimmed);
}

Future<String?> flipCameraVideoHorizontally({
  required String videoPath,
  required String outputPath,
  void Function(double progress)? onProgress,
}) async {
  if (!_isSafeFlipPath(videoPath) || !_isSafeFlipPath(outputPath)) {
    return null;
  }
  if (videoPath == outputPath) return null;
  if (FileSystemEntity.typeSync(videoPath, followLinks: false) !=
      FileSystemEntityType.file) {
    return null;
  }
  return VideoEditorBuilder(videoPath: videoPath)
      .flip(flipDirection: FlipDirection.horizontal)
      .export(outputPath: outputPath, onProgress: onProgress);
}
