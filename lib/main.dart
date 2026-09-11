import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'constants/app_colors.dart';
import 'screens/auth/splash_screen.dart';
import 'services/auth_scope.dart';
import 'services/auth_service.dart';
import 'services/document_scope.dart';
import 'services/document_service.dart';
import 'services/portfolio_scope.dart';
import 'services/portfolio_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const GradPortApp());
}

class GradPortApp extends StatefulWidget {
  const GradPortApp({
    super.key,
    this.authService,
    this.portfolioService,
    this.documentService,
  });

  final AuthService? authService;
  final PortfolioService? portfolioService;
  final DocumentService? documentService;

  @override
  State<GradPortApp> createState() => _GradPortAppState();
}

class _GradPortAppState extends State<GradPortApp> {
  late final AuthService _authService;
  late final bool _ownsAuthService;
  late final PortfolioService _portfolioService;
  late final bool _ownsPortfolioService;
  late final DocumentService _documentService;
  late final bool _ownsDocumentService;

  @override
  void initState() {
    super.initState();
    _ownsAuthService = widget.authService == null;
    _authService = widget.authService ?? AuthService();
    _ownsPortfolioService = widget.portfolioService == null;
    _portfolioService =
        widget.portfolioService ?? PortfolioService(authService: _authService);
    _ownsDocumentService = widget.documentService == null;
    _documentService =
        widget.documentService ?? DocumentService(authService: _authService);
  }

  @override
  void dispose() {
    if (_ownsDocumentService) _documentService.dispose();
    if (_ownsPortfolioService) _portfolioService.dispose();
    if (_ownsAuthService) _authService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthScope(
      authService: _authService,
      child: PortfolioScope(
        portfolioService: _portfolioService,
        child: DocumentScope(
          documentService: _documentService,
          child: MaterialApp(
            title: 'GradPort',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              useMaterial3: true,
              scaffoldBackgroundColor: AppColors.background,
              colorScheme: ColorScheme.fromSeed(
                seedColor: AppColors.primary,
                brightness: Brightness.light,
                primary: AppColors.primary,
                secondary: AppColors.secondary,
                surface: AppColors.surface,
              ),
              textTheme: GoogleFonts.poppinsTextTheme(),
              appBarTheme: AppBarTheme(
                backgroundColor: AppColors.headerBackground,
                foregroundColor: AppColors.headerText,
                elevation: 0,
                titleTextStyle: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                systemOverlayStyle: SystemUiOverlayStyle.light,
              ),
              // FIX: removed dialogTheme block — use showDialog with explicit decoration
              // instead. DialogTheme constructor signature changed in Material 3 and
              // caused: "argument type 'DialogTheme' can't be assigned to 'DialogThemeData'"
              snackBarTheme: SnackBarThemeData(
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: AppColors.primary,
                contentTextStyle: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
              bottomSheetTheme: const BottomSheetThemeData(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
              ),
            ),
            home: const SplashScreen(),
          ),
        ),
      ),
    );
  }
}
