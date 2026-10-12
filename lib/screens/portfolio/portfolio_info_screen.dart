// LOCATION: lib/screens/portfolio/portfolio_info_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/portfolio_scope.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/portfolio_models.dart';
import 'models/portfolio_schedule.dart';
import 'portfolio_summary_screen.dart';
import 'widgets/portfolio_schedule_picker.dart';
import 'widgets/portfolio_text_field.dart';
import 'widgets/step_indicator.dart';

/// Collects and persists portfolio title-page information.
class PortfolioInfoScreen extends StatefulWidget {
  const PortfolioInfoScreen({super.key, this.portfolio});

  final PortfolioRecord? portfolio;

  @override
  State<PortfolioInfoScreen> createState() => _PortfolioInfoScreenState();
}

class _PortfolioInfoScreenState extends State<PortfolioInfoScreen>
    with SingleTickerProviderStateMixin {
  bool _isSaving = false;
  PortfolioRecord? _createdPortfolio;
  Map<String, String> _errors = {};
  final _fieldKeys = {
    for (final key in PortfolioInfo.fieldLabels.keys) key: GlobalKey(),
  };
  final _focusNodes = {
    for (final key in PortfolioInfo.fieldLabels.keys.where(
      (key) => key != 'schedule',
    ))
      key: FocusNode(),
  };
  // ─── Controllers ─────────────────────────────────────────────────────────────
  final _fullNameCtrl = TextEditingController();
  final _yearSectionCtrl = TextEditingController();
  String? _scheduleDay;
  TimeOfDay? _scheduleStartTime;
  TimeOfDay? _scheduleEndTime;
  String? _legacySchedule;
  final _instructorCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _courseCodeCtrl = TextEditingController();
  final _semesterYearCtrl = TextEditingController();

  // ─── Entrance animation ───────────────────────────────────────────────────────
  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    final info = widget.portfolio?.info;
    if (info != null) {
      _fullNameCtrl.text = info.fullName;
      _yearSectionCtrl.text = info.yearAndSection;
      final parsedSchedule = PortfolioSchedule.tryParse(info.schedule);
      if (parsedSchedule == null) {
        _legacySchedule = info.schedule;
      } else {
        _scheduleDay = parsedSchedule.day;
        _scheduleStartTime = parsedSchedule.startTime;
        _scheduleEndTime = parsedSchedule.endTime;
      }
      _instructorCtrl.text = info.instructorName;
      _courseCtrl.text = info.course;
      _courseCodeCtrl.text = info.courseCode;
      _semesterYearCtrl.text = info.semesterAndYear;
    }
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _entranceCtrl,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _fullNameCtrl.dispose();
    _yearSectionCtrl.dispose();
    _instructorCtrl.dispose();
    _courseCtrl.dispose();
    _courseCodeCtrl.dispose();
    _semesterYearCtrl.dispose();
    _entranceCtrl.dispose();
    super.dispose();
  }

  // ─── Validation & navigation ──────────────────────────────────────────────────
  Future<void> _onNext() async {
    if (_isSaving) return;
    final schedule =
        _scheduleDay == null ||
            _scheduleStartTime == null ||
            _scheduleEndTime == null
        ? null
        : PortfolioSchedule(
            day: _scheduleDay!,
            startTime: _scheduleStartTime!,
            endTime: _scheduleEndTime!,
          );
    final info = PortfolioInfo(
      fullName: _fullNameCtrl.text.trim(),
      yearAndSection: _yearSectionCtrl.text.trim(),
      schedule: schedule?.formatted ?? '',
      instructorName: _instructorCtrl.text.trim(),
      course: _courseCtrl.text.trim(),
      courseCode: _courseCodeCtrl.text.trim(),
      semesterAndYear: _semesterYearCtrl.text.trim(),
    );

    final errors = info.validationErrors;
    final scheduleError = _scheduleDay == null
        ? 'Please select a schedule day.'
        : _scheduleStartTime == null
        ? 'Please select a start time.'
        : _scheduleEndTime == null
        ? 'Please select an end time.'
        : !schedule!.hasValidRange
        ? 'End time must be later than start time.'
        : null;
    if (scheduleError != null) errors['schedule'] = scheduleError;
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      final first = PortfolioInfo.fieldLabels.keys.firstWhere(
        errors.containsKey,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNodes[first]?.requestFocus();
        final fieldContext = _fieldKeys[first]?.currentContext;
        if (fieldContext != null) {
          Scrollable.ensureVisible(
            fieldContext,
            alignment: 0.05,
            duration: const Duration(milliseconds: 200),
          );
        }
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _isSaving = true);
    try {
      final service = PortfolioScope.of(context);
      final existing = widget.portfolio;
      if (existing != null) {
        await service.updatePortfolio(existing.id, info);
        if (mounted) Navigator.pop(context, true);
        return;
      }

      final created = _createdPortfolio;
      final saved = created == null
          ? await service.createPortfolio(info)
          : await service.updatePortfolio(created.id, info);
      _createdPortfolio = saved;
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 350),
          pageBuilder: (_, _, _) => PortfolioSummaryScreen(portfolio: saved),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: SlideTransition(
              position:
                  Tween<Offset>(
                    begin: const Offset(0.05, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                  ),
              child: child,
            ),
          ),
        ),
      );
    } on ApiException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Unable to save the portfolio. Please try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: widget.portfolio == null
            ? 'Generate Portfolio'
            : 'Edit Portfolio',
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Column(
            children: [
              // Scrollable form content
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Section label ──────────────────────────────
                      Text('Title Page', style: AppTextStyles.h3),
                      const SizedBox(height: 16),

                      // ── Full Name* ─────────────────────────────────
                      PortfolioTextField(
                        controller: _fullNameCtrl,
                        key: _fieldKeys['fullName'],
                        focusNode: _focusNodes['fullName'],
                        errorText: _errors['fullName'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('fullName')),
                        label: 'Full Name',
                        hint: 'Dela Cruz, John',
                        required: true,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Year & Section* ────────────────────────────
                      PortfolioTextField(
                        controller: _yearSectionCtrl,
                        key: _fieldKeys['yearAndSection'],
                        focusNode: _focusNodes['yearAndSection'],
                        errorText: _errors['yearAndSection'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('yearAndSection')),
                        label: 'Year & Section',
                        hint: 'e.g. 4BSIT-1',
                        required: true,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Schedule* ──────────────────────────────────
                      PortfolioSchedulePicker(
                        key: _fieldKeys['schedule'],
                        day: _scheduleDay,
                        startTime: _scheduleStartTime,
                        endTime: _scheduleEndTime,
                        legacyValue: _legacySchedule,
                        onDayChanged: (value) => setState(() {
                          _scheduleDay = value;
                          _legacySchedule = null;
                        }),
                        onStartTimeChanged: (value) => setState(() {
                          _scheduleStartTime = value;
                          _legacySchedule = null;
                        }),
                        onEndTimeChanged: (value) => setState(() {
                          _scheduleEndTime = value;
                          _legacySchedule = null;
                        }),
                      ),
                      if (_errors['schedule'] != null)
                        Text(
                          _errors['schedule']!,
                          style: const TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 14),

                      // ── Instructor's Name* ─────────────────────────
                      PortfolioTextField(
                        controller: _instructorCtrl,
                        key: _fieldKeys['instructorName'],
                        focusNode: _focusNodes['instructorName'],
                        errorText: _errors['instructorName'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('instructorName')),
                        label: "Instructor's Name",
                        hint: 'First Name, Middle Initial, Last name',
                        required: true,
                        keyboardType: TextInputType.name,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Course ─────────────────────────────────────
                      PortfolioTextField(
                        controller: _courseCtrl,
                        key: _fieldKeys['course'],
                        focusNode: _focusNodes['course'],
                        errorText: _errors['course'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('course')),
                        required: true,
                        label: 'Course',
                        hint: 'Free Elective',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Course Code ────────────────────────────────
                      PortfolioTextField(
                        controller: _courseCodeCtrl,
                        key: _fieldKeys['courseCode'],
                        focusNode: _focusNodes['courseCode'],
                        errorText: _errors['courseCode'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('courseCode')),
                        required: true,
                        label: 'Course Code',
                        hint: 'e.g. CCSFE4-18',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),

                      // ── Semester & Academic Year ───────────────────
                      PortfolioTextField(
                        controller: _semesterYearCtrl,
                        key: _fieldKeys['semesterAndYear'],
                        focusNode: _focusNodes['semesterAndYear'],
                        errorText: _errors['semesterAndYear'],
                        onChanged: (_) =>
                            setState(() => _errors.remove('semesterAndYear')),
                        required: true,
                        label: 'Semester & Academic Year',
                        hint: 'e.g. 2nd Semester, A.Y. 2025-2026',
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _onNext(),
                      ),

                      const SizedBox(height: 28),

                      // ── Next button ────────────────────────────────
                      _NextButton(
                        onPressed: _onNext,
                        label: widget.portfolio == null
                            ? 'Next'
                            : 'Save Changes',
                        isLoading: _isSaving,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.portfolio == null)
                Container(
                  color: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: const StepIndicatorLight(currentStep: 1),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Reusable Next / Action button for the portfolio flow ────────────────────
class _NextButton extends StatefulWidget {
  const _NextButton({
    required this.onPressed,
    this.label = 'Next',
    this.isLoading = false,
  });
  final VoidCallback onPressed;
  final String label;
  final bool isLoading;

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 180),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.97,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      onTap: widget.isLoading ? null : widget.onPressed,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (_, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.secondary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Center(
            child: widget.isLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
