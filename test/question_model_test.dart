import 'package:flutter_test/flutter_test.dart';
import 'package:question_bank_app/models/question.dart';

void main() {
  test('Question fromJson parses fields', () {
    final json = {
      'id': 'ap-2024-q001',
      'category': 'network',
      'year': 2024,
      'text': 'Sample question',
      'choices': ['A', 'B', 'C', 'D'],
      'answerIndex': 2,
      'explanation': 'Explanation',
      'sourceUrl': '',
    };

    final question = Question.fromJson(json);

    expect(question.id, 'ap-2024-q001');
    expect(question.category, 'network');
    expect(question.year, 2024);
    expect(question.text, 'Sample question');
    expect(question.choices, ['A', 'B', 'C', 'D']);
    expect(question.answerIndex, 2);
    expect(question.explanation, 'Explanation');
    expect(question.sourceUrl, isNull);
  });

  test('Question fromJson sanitizes empty choices and adjusts answerIndex', () {
    final json = {
      'id': 'ap-2024-q002',
      'category': 'network',
      'year': 2024,
      'text': 'Question with blanks',
      'choices': [' A ', '', '  ', 'B', null],
      'answerIndex': 3,
      'explanation': 'Explanation',
      'sourceUrl': '',
    };

    final question = Question.fromJson(json);

    expect(question.choices, ['A', 'B']);
    expect(question.answerIndex, 1);
  });
}
