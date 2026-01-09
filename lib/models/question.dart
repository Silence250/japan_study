import 'dart:convert';

import 'package:flutter/foundation.dart';

class Question {
  const Question({
    required this.id,
    required this.category,
    required this.year,
    required this.text,
    required this.choices,
    required this.answerIndex,
    required this.explanation,
    this.sourceUrl,
  });

  final String id;
  final String category;
  final int year;
  final String text;
  final List<String> choices;
  final int answerIndex;
  final String explanation;
  final String? sourceUrl;

  factory Question.fromJson(Map<String, dynamic> json) {
    final rawChoices = (json['choices'] as List<dynamic>? ?? const [])
        .map((choice) => choice == null ? '' : choice.toString())
        .toList();
    final sanitizedAnswerIndex = sanitizeChoices(
      rawChoices,
      json['answerIndex'] as int? ?? -1,
      questionId: json['id'] as String?,
    );
    return Question(
      id: json['id'] as String,
      category: json['category'] as String,
      year: json['year'] as int,
      text: json['text'] as String,
      choices: rawChoices,
      answerIndex: sanitizedAnswerIndex,
      explanation: json['explanation'] as String,
      sourceUrl: (json['sourceUrl'] as String?)?.isEmpty == true
          ? null
          : json['sourceUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category': category,
      'year': year,
      'text': text,
      'choices': choices,
      'answerIndex': answerIndex,
      'explanation': explanation,
      'sourceUrl': sourceUrl ?? '',
    };
  }

  static List<String> decodeChoices(String json) {
    return (jsonDecode(json) as List<dynamic>)
        .map((choice) => choice as String)
        .toList();
  }

  static String encodeChoices(List<String> choices) {
    return jsonEncode(choices);
  }

  static int sanitizeChoices(
    List<String> choices,
    int answerIndex, {
    String? questionId,
  }) {
    final cleaned = <String>[];
    int? newAnswerIndex;
    for (var i = 0; i < choices.length; i++) {
      final trimmed = choices[i].trim();
      if (trimmed.isEmpty) {
        continue;
      }
      if (i == answerIndex) {
        newAnswerIndex = cleaned.length;
      }
      cleaned.add(trimmed);
    }
    if (kDebugMode && cleaned.length != choices.length) {
      debugPrint(
        'Question ${questionId ?? ''} has empty choices; '
        'removed ${choices.length - cleaned.length}.',
      );
    }
    choices
      ..clear()
      ..addAll(cleaned);
    if (newAnswerIndex == null && answerIndex != -1 && kDebugMode) {
      debugPrint(
        'Question ${questionId ?? ''} answerIndex $answerIndex '
        'is invalid after sanitization.',
      );
    }
    return newAnswerIndex ?? -1;
  }
}

class QuestionsSeed {
  const QuestionsSeed({
    required this.version,
    required this.questions,
    this.generatedAt,
    this.sourceSessions = const [],
  });

  final int version;
  final List<Question> questions;
  final String? generatedAt;
  final List<String> sourceSessions;

  factory QuestionsSeed.fromJson(Map<String, dynamic> json) {
    return QuestionsSeed(
      version: json['version'] as int,
      questions: (json['questions'] as List<dynamic>)
          .map(
            (question) => Question.fromJson(question as Map<String, dynamic>),
          )
          .toList(),
      generatedAt: json['generatedAt'] as String?,
      sourceSessions: (json['sourceSessions'] as List<dynamic>?)
              ?.whereType<String>()
              .toList() ??
          const [],
    );
  }
}
