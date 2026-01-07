import 'dart:convert';

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
    return Question(
      id: json['id'] as String,
      category: json['category'] as String,
      year: json['year'] as int,
      text: json['text'] as String,
      choices: (json['choices'] as List<dynamic>)
          .map((choice) => choice as String)
          .toList(),
      answerIndex: json['answerIndex'] as int,
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
}

class QuestionsSeed {
  const QuestionsSeed({required this.version, required this.questions});

  final int version;
  final List<Question> questions;

  factory QuestionsSeed.fromJson(Map<String, dynamic> json) {
    return QuestionsSeed(
      version: json['version'] as int,
      questions: (json['questions'] as List<dynamic>)
          .map(
            (question) => Question.fromJson(question as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
