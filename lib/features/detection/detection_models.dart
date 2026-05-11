import 'package:flutter/material.dart';

class DetectionBox {
  DetectionBox({
    required this.rect,
    required this.score,
    this.classId,
    this.label,
    this.colorName,
    this.colorHex,
    this.colorTags = const [],
  });

  final Rect rect;
  final double score;
  final int? classId;
  final String? label;
  final String? colorName;
  final String? colorHex;
  final List<String> colorTags;

  DetectionBox copyWith({
    Rect? rect,
    double? score,
    int? classId,
    String? label,
    String? colorName,
    String? colorHex,
    List<String>? colorTags,
  }) {
    return DetectionBox(
      rect: rect ?? this.rect,
      score: score ?? this.score,
      classId: classId ?? this.classId,
      label: label ?? this.label,
      colorName: colorName ?? this.colorName,
      colorHex: colorHex ?? this.colorHex,
      colorTags: colorTags ?? this.colorTags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'score': score,
      'classId': classId,
      'label': label,
      'colorName': colorName,
      'colorHex': colorHex,
      'colorTags': colorTags,
    };
  }

  factory DetectionBox.fromJson(Map<String, dynamic> json) {
    return DetectionBox(
      rect: Rect.fromLTRB(
        (json['left'] as num).toDouble(),
        (json['top'] as num).toDouble(),
        (json['right'] as num).toDouble(),
        (json['bottom'] as num).toDouble(),
      ),
      score: (json['score'] as num).toDouble(),
      classId: json['classId'] as int?,
      label: json['label'] as String?,
      colorName: json['colorName'] as String?,
      colorHex: json['colorHex'] as String?,
      colorTags: (json['colorTags'] as List<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false),
    );
  }
}
