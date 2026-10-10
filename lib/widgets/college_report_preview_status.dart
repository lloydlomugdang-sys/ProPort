import 'package:flutter/material.dart';
import '../services/college_report_scope.dart';

/// The exported PDF is a snapshot. Later edits require a new PDF generation.
class CollegeReportPreviewStatus extends StatefulWidget {
  const CollegeReportPreviewStatus({super.key});
  @override
  State<CollegeReportPreviewStatus> createState() =>
      _CollegeReportPreviewStatusState();
}

class _CollegeReportPreviewStatusState
    extends State<CollegeReportPreviewStatus> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = CollegeReportScope.maybeOf(context);
    if (service != null &&
        !service.loaded &&
        !service.isLoading &&
        service.errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) service.load();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = CollegeReportScope.maybeOf(context);
    if (service == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'College Report',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          if (!service.loaded && service.errorMessage == null)
            const LinearProgressIndicator()
          else if (service.errorMessage != null && !service.loaded) ...[
            const Text('Unable to check saved questionnaire responses.'),
            TextButton(onPressed: service.load, child: const Text('Retry')),
          ] else if (service.saved == null)
            const Text(
              'No official questionnaire saved. Open Files → College Report to complete it.',
            )
          else
            Text(
              'Saved questionnaire: ${service.saved!.answeredCount} of ${service.template!.questions.length} answered. Unanswered items remain unanswered.${service.saved!.essay.trim().isEmpty ? '' : ' Student-written essay saved.'} Included when you generate a new PDF; existing PDFs are unchanged.',
            ),
          if (service.dirty)
            const Text('Unsaved questionnaire edits are not included.'),
        ],
      ),
    );
  }
}
