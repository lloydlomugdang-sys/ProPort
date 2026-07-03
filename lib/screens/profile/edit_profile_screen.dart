// LOCATION: lib/screens/profile/edit_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_text_styles.dart';
import '../../widgets/grad_app_bar.dart';
import 'models/user_profile_model.dart';
import 'widgets/profile_avatar.dart';
import 'widgets/profile_info_row.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen>
    with SingleTickerProviderStateMixin {
  // Local editable copy of the profile
  late String _fullName;
  late String _email;
  late String _program;
  late String _yearLevel;
  late String _school;
  String? _avatarPath;

  bool _hasChanges = false;
  bool _isSaving   = false;

  late final AnimationController _entranceCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();

    final p   = userProfileNotifier.profile;
    _fullName  = p.fullName;
    _email     = p.email;
    _program   = p.program;
    _yearLevel = p.yearLevel;
    _school    = p.school;
    _avatarPath = p.avatarPath;

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
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

  // ─── Avatar picker ────────────────────────────────────────────────────────
  Future<void> _onAvatarTap() async {
    try {
      final picker = ImagePicker();
      final result = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (result != null && mounted) {
        setState(() {
          _avatarPath  = result.path;
          _hasChanges  = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      _showInfo(
        'Image Picker',
        'Image picker integration will be connected in the next implementation phase.',
      );
    }
  }

  // ─── Inline field editor ──────────────────────────────────────────────────
  Future<void> _editField({
    required String title,
    required String currentValue,
    required ValueChanged<String> onSaved,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final ctrl = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.h3),
        content: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.inputBorder),
          ),
          child: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: keyboardType,
            style: GoogleFonts.poppins(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13),
              border: InputBorder.none,
              hintStyle: GoogleFonts.poppins(
                  fontSize: 14, color: AppColors.textMuted),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: Text('Save',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );

    ctrl.dispose();

    if (result != null && result.isNotEmpty && result != currentValue) {
      setState(() {
        onSaved(result);
        _hasChanges = true;
      });
    }
  }

  // ─── Save all changes ─────────────────────────────────────────────────────
  Future<void> _onSave() async {
    if (!_hasChanges) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isSaving = true);
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    // Update the in-memory notifier — listeners (ProfileScreen) rebuild
    // TODO: replace with MongoDB / API call
    userProfileNotifier.updateProfile(UserProfile(
      fullName:   _fullName,
      email:      _email,
      program:    _program,
      yearLevel:  _yearLevel,
      school:     _school,
      avatarPath: _avatarPath,
    ));

    setState(() => _isSaving = false);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Profile updated (Development Mode)',
          style: GoogleFonts.poppins(fontSize: 13, color: Colors.white)),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      duration: const Duration(seconds: 2),
    ));

    Navigator.pop(context);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  void _showInfo(String title, String content) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.h3),
        content: Text(content,
            style: AppTextStyles.bodySmall.copyWith(height: 1.6)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: AppTextStyles.labelLarge
                    .copyWith(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.edit_outlined,
                      color: AppColors.headerText, size: 22),
                  onPressed: _onSave,
                  tooltip: 'Save',
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
              // ── Avatar (tappable) ────────────────────────────────
              ProfileAvatar(
                avatarPath: _avatarPath,
                size: 110,
                showEditBadge: true,
                onTap: _onAvatarTap,
              ),
              const SizedBox(height: 16),

              // Full name (tappable)
              GestureDetector(
                onTap: () => _editField(
                  title: 'Full Name',
                  currentValue: _fullName,
                  onSaved: (v) => _fullName = v,
                  keyboardType: TextInputType.name,
                ),
                child: Text(
                  _fullName,
                  style: AppTextStyles.h2.copyWith(color: AppColors.primary),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 28),

              // ── Editable info card ───────────────────────────────
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
                    EditableInfoRow(
                      icon: Icons.email_outlined,
                      value: _email,
                      onEdit: () => _editField(
                        title: 'Email',
                        currentValue: _email,
                        onSaved: (v) => _email = v,
                        keyboardType: TextInputType.emailAddress,
                      ),
                    ),
                    EditableInfoRow(
                      icon: Icons.school_outlined,
                      value: _program,
                      onEdit: () => _editField(
                        title: 'Program',
                        currentValue: _program,
                        onSaved: (v) => _program = v,
                      ),
                    ),
                    EditableInfoRow(
                      icon: Icons.calendar_today_outlined,
                      value: _yearLevel,
                      onEdit: () => _editField(
                        title: 'Year Level',
                        currentValue: _yearLevel,
                        onSaved: (v) => _yearLevel = v,
                      ),
                    ),
                    EditableInfoRow(
                      icon: Icons.account_balance_outlined,
                      value: _school,
                      isLast: true,
                      onEdit: () => _editField(
                        title: 'School',
                        currentValue: _school,
                        onSaved: (v) => _school = v,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Save button ──────────────────────────────────────
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
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white),
                          ),
                        )
                      : Text('Save Changes',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}