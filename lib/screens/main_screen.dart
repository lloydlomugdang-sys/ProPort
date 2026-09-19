// LOCATION: lib/screens/main_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';
import '../services/batch_upload_queue.dart';
import '../services/document_picker.dart';
import '../services/document_scope.dart';
import '../widgets/bottom_nav_bar.dart';
import 'files/add_file_screen.dart';
import 'files/batch_review_screen.dart';
import 'files/files_screen.dart';
import 'home/home_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart' show SettingsScreen;

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.filePicker});

  static const routeName = '/main';

  final DocumentPicker? filePicker;

  /// Returns to the existing MainScreen, popping all routes above it,
  /// and ensures the Dashboard (Home) tab is selected.
  static void returnToDashboard(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.popUntil((route) {
      return route.settings.name == routeName || route.isFirst;
    });
    MainScreenState._activeInstance?.selectTab(0);
  }

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen>
    with SingleTickerProviderStateMixin {
  static MainScreenState? _activeInstance;

  int _currentIndex = 0;
  bool _isAddExpanded = false;

  late final AnimationController _quickActionCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _scaleAnim;
  late final DocumentPicker _filePicker;

  List<Widget> get _pages => [
        const HomeScreen(),
        const FilesScreen(),
        const ProfileScreen(),
        const SettingsScreen(),
      ];

  @override
  void initState() {
    super.initState();
    _activeInstance = this;
    _filePicker = widget.filePicker ?? DeviceDocumentPicker();
    _quickActionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _fadeAnim = CurvedAnimation(
      parent: _quickActionCtrl,
      curve: Curves.easeOutCubic,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _quickActionCtrl,
        curve: Curves.easeOutCubic,
      ),
    );
    _scaleAnim = Tween<double>(begin: 0.90, end: 1.0).animate(
      CurvedAnimation(
        parent: _quickActionCtrl,
        curve: Curves.easeOutCubic,
      ),
    );
    _quickActionCtrl.addStatusListener((status) {
      if (status == AnimationStatus.dismissed ||
          status == AnimationStatus.completed) {
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    if (_activeInstance == this) {
      _activeInstance = null;
    }
    _quickActionCtrl.dispose();
    super.dispose();
  }

  void selectTab(int index) {
    if (_isAddExpanded) _closeAddMenu();
    if (_currentIndex != index) {
      setState(() => _currentIndex = index);
    }
  }

  void _onTabChanged(int index) {
    if (_isAddExpanded) _closeAddMenu();
    setState(() => _currentIndex = index);
  }

  void _toggleAddMenu() {
    if (_isAddExpanded) {
      _closeAddMenu();
    } else {
      _openAddMenu();
    }
  }

  void _openAddMenu() {
    setState(() => _isAddExpanded = true);
    _quickActionCtrl.forward();
  }

  void _closeAddMenu() {
    if (!_isAddExpanded && _quickActionCtrl.value == 0) return;
    setState(() => _isAddExpanded = false);
    _quickActionCtrl.reverse();
  }

  Future<void> _onQuickActionCamera() async {
    _closeAddMenu();
    try {
      final photo = await _filePicker.pickFromCamera();
      if (photo == null || !mounted) return;

      final service = DocumentScope.of(context);
      await Navigator.push<bool>(
        context,
        PageRouteBuilder(
          pageBuilder: (_, _, _) => DocumentScope(
            documentService: service,
            child: AddFileScreen(
              initialFiles: [photo],
              filePicker: _filePicker,
            ),
          ),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, anim, _, child) => FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: child,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to capture from camera. Please try again.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
  }

  Future<void> _onQuickActionFileUpload() async {
    _closeAddMenu();
    try {
      final selected = await _filePicker.pickDocuments(allowMultiple: true);
      if (selected == null || selected.isEmpty || !mounted) return;

      if (selected.length > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'You can select up to 20 documents. Selected: ${selected.length}.',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
        return;
      }

      if (selected.length == 1) {
        final service = DocumentScope.of(context);
        await Navigator.push<bool>(
          context,
          PageRouteBuilder(
            pageBuilder: (_, _, _) => DocumentScope(
              documentService: service,
              child: AddFileScreen(
                initialFiles: selected,
                filePicker: _filePicker,
              ),
            ),
            transitionDuration: const Duration(milliseconds: 300),
            transitionsBuilder: (_, anim, _, child) => FadeTransition(
              opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
              child: child,
            ),
          ),
        );
      } else {
        // 2–20 files: delegate to BatchUploadQueue / BatchReviewScreen
        final service = DocumentScope.of(context);
        final queue = BatchUploadQueue(documentService: service);
        queue.initialize(selected);
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => DocumentScope(
              documentService: service,
              child: BatchReviewScreen(queue: queue),
            ),
          ),
        );
        if (result == true && mounted) {
          await service.load(force: true);
        }
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to read the selected file. Please try another file.',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
          ),
          backgroundColor: AppColors.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
    }
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.cardBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isAddExpanded,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isAddExpanded) {
          _closeAddMenu();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: Stack(
          children: [
            SafeArea(
              top: false,
              bottom: false,
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
            AnimatedBuilder(
              animation: _quickActionCtrl,
              builder: (context, _) {
                if (!_isAddExpanded && _quickActionCtrl.value == 0) {
                  return const SizedBox.shrink();
                }
                return Stack(
                  children: [
                    // Scrim over page content when quick actions are open
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: _closeAddMenu,
                        behavior: HitTestBehavior.opaque,
                        child: FadeTransition(
                          opacity: _fadeAnim,
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                    ),
                    // Expandable quick action buttons floating directly above the center FAB
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 12,
                      child: FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: ScaleTransition(
                            scale: _scaleAnim,
                            alignment: Alignment.bottomCenter,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildQuickActionItem(
                                  icon: Icons.camera_alt_rounded,
                                  label: 'Camera',
                                  onTap: _onQuickActionCamera,
                                ),
                                const SizedBox(height: 10),
                                _buildQuickActionItem(
                                  icon: Icons.upload_file_rounded,
                                  label: 'File Upload',
                                  onTap: _onQuickActionFileUpload,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
        bottomNavigationBar: GradBottomNavBar(
          currentIndex: _currentIndex,
          onTabChanged: _onTabChanged,
          onAddTapped: _toggleAddMenu,
          isAddExpanded: _isAddExpanded,
        ),
      ),
    );
  }
}