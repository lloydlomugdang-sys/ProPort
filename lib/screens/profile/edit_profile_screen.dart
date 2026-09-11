import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../services/api_client.dart';
import '../../services/auth_scope.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/user_profile_model.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_info_row.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.profile});

  final UserProfile profile;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  late String _firstName;
  late String _lastName;
  late String _program;
  late String _yearLevel;
  late String _school;

  bool _hasChanges = false;
  bool _isSaving = false;

  late final AnimationController _entranceCtrl;
  late final Animation<double> _fadeAnim;

  String get _fullName => '$_firstName $_lastName'.trim();

  @override
  void initState() {
    super.initState();
    _firstName = widget.profile.firstName;
    _lastName = widget.profile.lastName;
    _program = widget.profile.program;
    _yearLevel = widget.profile.yearLevel;
    _school = widget.profile.school;

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
    final firstNameController = TextEditingController(text: _firstName);
    final lastNameController = TextEditingController(text: _lastName);
    String? validationMessage;

    final result = await showDialog<(String, String)>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                if (!_validName(firstName) || !_validName(lastName)) {
                  setDialogState(() {
                    validationMessage =
                        'First and last name must each contain 2-100 characters.';
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
    if (result == null || (result.$1 == _firstName && result.$2 == _lastName)) {
      return;
    }
    setState(() {
      _firstName = result.$1;
      _lastName = result.$2;
      _hasChanges = true;
    });
  }

  Future<void> _editField({
    required String title,
    required String currentValue,
    required int maxLength,
    required ValueChanged<String> onSaved,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.h3),
        content: _dialogTextField(
          controller: controller,
          label: title,
          maxLength: maxLength,
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
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(
              'Save',
              style: AppTextStyles.labelLarge.copyWith(
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 300), controller.dispose);
    if (result == null || result == currentValue) return;
    setState(() {
      onSaved(result);
      _hasChanges = true;
    });
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

  bool _validName(String value) => value.length >= 2 && value.length <= 100;

  Future<void> _onSave() async {
    if (_isSaving) return;
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    if (!_validName(_firstName) || !_validName(_lastName)) {
      _showSnackBar(
        'First and last name must each contain 2-100 characters.',
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
      _showSnackBar(_safeErrorMessage(error), isError: true);
    }
  }

  String _safeErrorMessage(Object error) {
    if (error is ApiException) {
      final fieldValue = error.fields.values.isEmpty
          ? null
          : error.fields.values.first;
      if (fieldValue is List && fieldValue.isNotEmpty) {
        return fieldValue.first.toString();
      }
      if (fieldValue is String && fieldValue.isNotEmpty) return fieldValue;
      if (error.statusCode == 401 || error.code == 'UNAUTHORIZED') {
        return 'Your session has expired. Please log in again.';
      }
      return error.message;
    }
    return 'Unable to update your profile. Please try again.';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradAppBar(
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
              const ProfileAvatar(size: 110),
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
                    EditableInfoRow(
                      icon: Icons.school_outlined,
                      value: _program,
                      onEdit: () => _editField(
                        title: 'Program',
                        currentValue: _program,
                        maxLength: 200,
                        onSaved: (value) => _program = value,
                      ),
                    ),
                    EditableInfoRow(
                      icon: Icons.calendar_today_outlined,
                      value: _yearLevel,
                      onEdit: () => _editField(
                        title: 'Year Level',
                        currentValue: _yearLevel,
                        maxLength: 50,
                        onSaved: (value) => _yearLevel = value,
                      ),
                    ),
                    EditableInfoRow(
                      icon: Icons.account_balance_outlined,
                      value: _school,
                      isLast: true,
                      onEdit: () => _editField(
                        title: 'School',
                        currentValue: _school,
                        maxLength: 200,
                        onSaved: (value) => _school = value,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _onSave,
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
