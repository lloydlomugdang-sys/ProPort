import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/college_report_models.dart';
import '../../services/college_report_scope.dart';
import '../../services/college_report_service.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/primary_button.dart';
import '../main_screen.dart';

class CollegeReportScreen extends StatefulWidget {
  const CollegeReportScreen({super.key});
  @override
  State<CollegeReportScreen> createState() => _CollegeReportScreenState();
}

class _CollegeReportScreenState extends State<CollegeReportScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = CollegeReportScope.of(context);
    if (!service.loaded && !service.isLoading && service.errorMessage == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) service.load();
      });
    }
  }

  Future<void> _save(CollegeReportService service) async {
    final saved = await service.save();
    if (!mounted || !saved) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('College Report saved.')));
  }

  @override
  Widget build(BuildContext context) {
    final service = CollegeReportScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'College Report'),
      bottomNavigationBar: service.loaded
          ? SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: 'Save Responses',
                    icon: Icons.save_outlined,
                    onPressed: () => _save(service),
                    isLoading: service.isSaving,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: service.isSaving
                        ? null
                        : () => MainScreen.returnToDashboard(context),
                    icon: const Icon(Icons.dashboard_rounded),
                    label: const Text('Back to Dashboard'),
                  ),
                ],
              ),
            )
          : null,
      body: !service.loaded
          ? Center(
              child: service.errorMessage == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(service.errorMessage!),
                        ),
                        TextButton(
                          onPressed: () => service.load(force: true),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.template!.title, style: AppTextStyles.h3),
                  const SizedBox(height: 10),
                  Text(
                    service.template!.instructions,
                    style: AppTextStyles.bodySmall,
                  ),
                  const Text(
                    'All responses are optional. Tap a selected choice again to leave it unanswered. Only saved responses appear in a newly generated portfolio.',
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Best completed near the end of your program, especially 4th year / 2nd semester. You can start earlier and save optional responses at any time.',
                    ),
                  ),
                  if (service.hasLegacyReport)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Your earlier six-question report is retained separately. Please complete this official questionnaire; old answers have not been mapped.',
                      ),
                    ),
                  if (service.isLoading) const LinearProgressIndicator(),
                  if (service.draftWarning != null)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(service.draftWarning!),
                    ),
                  const SizedBox(height: 16),
                  for (final section in service.template!.sections)
                    _ReportSection(
                      key: ValueKey('${service.draftRevision}-${section.id}'),
                      section: section,
                      service: service,
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Student-written essay / objectives (optional)',
                    style: AppTextStyles.bodyMedium,
                  ),
                  const Text(
                    'Write your own reflection or objectives. GradPort does not generate answers or an essay for you.',
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: ValueKey('essay-${service.draftRevision}'),
                    initialValue: service.essay,
                    enabled: !service.isSaving,
                    minLines: 4,
                    maxLines: 12,
                    maxLength: 10000,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Your essay / objectives',
                    ),
                    onChanged: service.setEssay,
                  ),
                  if (service.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        service.errorMessage!,
                        style: const TextStyle(color: AppColors.danger),
                      ),
                    ),
                  Text(
                    service.dirty
                        ? 'Unsaved changes'
                        : service.saved == null
                        ? 'Not saved yet'
                        : 'Saved to your account',
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }
}

class _ReportSection extends StatelessWidget {
  const _ReportSection({
    super.key,
    required this.section,
    required this.service,
  });
  final CollegeReportSection section;
  final CollegeReportService service;

  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    margin: const EdgeInsets.only(bottom: 14),
    child: ExpansionTile(
      key: PageStorageKey(section.id),
      maintainState: true,
      title: Text(
        '${section.label} ${section.prompt}',
        style: AppTextStyles.bodySmall,
      ),
      childrenPadding: const EdgeInsets.all(16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(section.note!),
          ),
        for (final question in section.questions)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (question.label.isNotEmpty ||
                    question.text != section.prompt)
                  Text(
                    '${question.label} ${question.text}'.trim(),
                    style: AppTextStyles.bodySmall,
                  ),
                const SizedBox(height: 8),
                if (section.responseType == 'text')
                  TextFormField(
                    key: ValueKey(question.key),
                    initialValue:
                        service.answers[question.key] as String? ?? '',
                    enabled: !service.isSaving,
                    minLines: 2,
                    maxLines: 6,
                    maxLength: 5000,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Your response (optional)',
                    ),
                    onChanged: (value) => service.answer(question.key, value),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final option in section.options)
                        ChoiceChip(
                          key: ValueKey('${question.key}-${option.value}'),
                          label: Text(option.label),
                          selected:
                              service.answers[question.key] == option.value,
                          onSelected: service.isSaving
                              ? null
                              : (selected) => service.answer(
                                  question.key,
                                  selected ? option.value : null,
                                ),
                        ),
                    ],
                  ),
                if (service.answers[question.key] == null)
                  const Text(
                    'Unanswered',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
