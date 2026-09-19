import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/form_validation.dart';
import '../../services/profile_options.dart';
import '../auth/widgets/auth_form_feedback.dart';
import '../../services/auth_scope.dart';
import '../../services/auth_service.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/user_profile_model.dart';
import 'widgets/avatar_action_sheet.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_info_row.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin, AuthFormFeedback<EditProfileScreen> {
  late String _firstName;
  late String _lastName;
  late String _program;
  late String _yearLevel;
  late String _school;

  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isAvatarLoading = false;
  bool _optionsRequested = false;
  ProfileOptions? _options;
  String? _optionsError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_optionsRequested) {
      _optionsRequested = true;
      _loadOptions();
    }
  }

  Future<void> _loadOptions() async {
    try {
      final options = await AuthScope.of(context).fetchProfileOptions();
      if (!mounted) return;
      setState(() {
        _options = options;
        _optionsError = null;
        if (_school.trim().isEmpty) {
          _school = options.school;
          _hasChanges = true;
        }
      });
    } catch (error) {
      if (mounted) setState(() => _optionsError = authFormError(error));
    }
  }

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;

  String get _fullName => '$_firstName $_lastName'.trim();

  @override
  void initState() {
    super.initState();
    _firstName = widget.profile.firstName;
    _lastName = widget.profile.lastName;
    _program = widget.profile.program.trim();
    _yearLevel = widget.profile.yearLevel.trim();
    _school = widget.profile.school.trim();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0, 0.8, curve: Curves.easeOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _editName() async {
    if (_isSaving) return;
    final firstNameController = TextEditingController(text: _firstName);
    final lastNameController = TextEditingController(text: _lastName);
    String? validationMessage;

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          scrollable: true,
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('Full Name', style: AppTextStyles.h3),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dialogTextField(
                controller: firstNameController,
                label: 'First Name',
                keyboardType: TextInputType.name,
              ),
              const SizedBox(height: 12),
              _dialogTextField(
                controller: lastNameController,
                label: 'Last Name',
                keyboardType: TextInputType.name,
              ),
              if (validationMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  validationMessage!,
                  style: AppTextStyles.bodySmall.copyWith(color: Colors.red),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                final firstName = firstNameController.text.trim();
                final lastName = lastNameController.text.trim();
                final error =
                    personalNameError(firstName) ?? personalNameError(lastName);
                if (error != null) {
                  setDialogState(() {
                    validationMessage = error;
                  });
                  return;
                }
                Navigator.pop(context, (firstName, lastName));
              },
              child: Text(
                'Save',
                style: AppTextStyles.labelLarge.copyWith(
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 300), () {
      firstNameController.dispose();
      lastNameController.dispose();
    });
    if (!mounted ||
        result == null ||
        (result.$1 == _firstName && result.$2 == _lastName)) {
      return;
    }
    setState(() {
      _firstName = result.$1;
      _lastName = result.$2;
      _hasChanges = true;
    });
  }

  Widget _selection({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
  }) {
    // Preserve an existing legacy value, but do not offer it as a new choice.
    final values = <String>{'', ...options, if (value.isNotEmpty) value};
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        key: ValueKey(label),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
          border: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.divider),
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.divider),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: AppColors.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
        items: values
            .map(
              (item) => DropdownMenuItem(
                value: item,
                enabled: item.isEmpty || options.contains(item),
                child: Text(
                  item.isEmpty ? '$label not set' : item,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: item.isEmpty
                        ? AppColors.textMuted
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: _isSaving || _options == null
            ? null
            : (selected) {
                if (selected == null) return;
                setState(() {
                  onChanged(selected);
                  _hasChanges = true;
                });
              },
      ),
    );
  }

  Widget _dialogTextField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.inputBorder),
      ),
      child: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        maxLength: maxLength,
        style: GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
          border: InputBorder.none,
          hintStyle: GoogleFonts.poppins(
            fontSize: 14,
            color: AppColors.textMuted,
          ),
        ),
      ),
    );
  }

  Future<void> _onSave() async {
    if (_isSaving || isRateLimited || _options == null) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    final nameError =
        personalNameError(_firstName) ?? personalNameError(_lastName);
    if (nameError != null) {
      _showSnackBar(nameError, isError: true);
      return;
    }

    if (_program.trim().isEmpty) {
      _showSnackBar('Please select a supported program.', isError: true);
      return;
    }
    if (_yearLevel.trim().isEmpty) {
      _showSnackBar(
        'Please select a year level from 1st Year to 4th Year.',
        isError: true,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await AuthScope.of(context).updateCurrentUserProfile(
        firstName: _firstName,
        lastName: _lastName,
        program: _program,
        yearLevel: _yearLevel,
        school: _school,
      );
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _hasChanges = false;
      });
      _showSnackBar('Profile updated successfully.');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnackBar(handleFormError(error), isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
        ),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleAvatarTap(AuthService auth) async {
    await showAvatarActionSheet(
      context: context,
      authService: auth,
      onLoadingChanged: (loading) {
        if (mounted) setState(() => _isAvatarLoading = loading);
      },
      onFeedback: (message, {bool isError = false}) {
        if (mounted) _showSnackBar(message, isError: isError);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradBackAppBar(
        title: 'Profile',
        actions: [
          _isSaving
              ? const Padding(
                  padding: EdgeInsets.only(right: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.headerText,
                    size: 22,
                  ),
                  onPressed: _onSave,
                  tooltip: 'Save profile',
                ),
        ],
      ),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
          child: Column(
            children: [
              ProfileAvatar(
                size: 110,
                avatarBytes: auth.avatarBytes,
                initials: widget.profile.initials,
                showEditBadge: true,
                isLoading: _isAvatarLoading,
                onTap: () => _handleAvatarTap(auth),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _editName,
                child: Text(
                  _fullName,
                  style: AppTextStyles.h2.copyWith(color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.cardBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    ProfileInfoRow(
                      icon: Icons.email_outlined,
                      value: widget.profile.email,
                    ),
                    _selection(
                      label: 'Program',
                      options: _options?.programs ?? [],
                      value: _program,
                      onChanged: (value) => _program = value,
                    ),
                    _selection(
                      label: 'Year Level',
                      options: _options?.yearLevels ?? [],
                      value: _yearLevel,
                      onChanged: (value) => _yearLevel = value,
                    ),
                    ProfileInfoRow(
                      icon: Icons.account_balance_outlined,
                      value: _school,
                      isLast: true,
                      isLocked: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              if (_options == null && _optionsError == null)
                const CircularProgressIndicator(),
              if (_optionsError != null) ...[
                Text(_optionsError!),
                TextButton(onPressed: _loadOptions, child: const Text('Retry')),
              ],
              AuthRetryNotice(seconds: retrySeconds),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving || isRateLimited || _options == null
                      ? null
                      : _onSave,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : Text(
                          'Save Changes',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
