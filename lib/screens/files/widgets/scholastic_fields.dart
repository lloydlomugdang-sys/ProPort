import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/scholastic_details.dart';

class ScholasticFields extends StatelessWidget {
  const ScholasticFields({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final ScholasticDetails value;
  final ValueChanged<ScholasticDetails> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('TOR coverage — year and semester covered by this record'),
      TextFormField(
        initialValue: value.studyYear?.toString() ?? '',
        enabled: enabled,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        decoration: const InputDecoration(
          labelText: 'Year of study',
          hintText: 'For example: 1',
        ),
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (text) =>
            text == null ||
                text.isEmpty ||
                (int.tryParse(text) ?? 0) >= 1 &&
                    (int.tryParse(text) ?? 0) <= 20
            ? null
            : 'Enter a year from 1 to 20.',
        onChanged: (text) {
          final year = int.tryParse(text);
          onChanged(
            ScholasticDetails(
              studyYear: year != null && year >= 1 && year <= 20 ? year : null,
              semester: value.semester,
              reflectionIncluded: value.reflectionIncluded,
            ),
          );
        },
      ),
      DropdownButtonFormField<String>(
        initialValue: value.semester,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Semester covered'),
        items: [
          for (final term in ScholasticDetails.semesters)
            DropdownMenuItem(value: term, child: Text(term)),
        ],
        onChanged: enabled
            ? (term) => onChanged(
                ScholasticDetails(
                  studyYear: value.studyYear,
                  semester: term,
                  reflectionIncluded: value.reflectionIncluded,
                ),
              )
            : null,
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text(
          'Reflection is already included in this uploaded document',
        ),
        value: value.reflectionIncluded,
        onChanged: enabled
            ? (checked) => onChanged(
                ScholasticDetails(
                  studyYear: value.studyYear,
                  semester: value.semester,
                  reflectionIncluded: checked ?? false,
                ),
              )
            : null,
      ),
      if (!value.reflectionIncluded)
        const Text('Enter your reflection below before saving.'),
      const Text(
        'A recorded period does not automatically complete your full scholastic requirements.',
      ),
    ],
  );
}
