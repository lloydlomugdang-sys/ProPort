// LOCATION: lib/screens/settings/about_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../widgets/grad_app_bar.dart';
import 'widgets/info_card.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOutCubic,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _entranceCtrl.forward();
    });
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'About GradPort'),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── App hero ─────────────────────────────────────
                _buildHero(),

                const SizedBox(height: 28),

                // ── Mission & Vision ──────────────────────────────
                _buildMissionCard(),

                const SizedBox(height: 24),

                // ── Key Features ──────────────────────────────────
                _sectionLabel('Key Features'),
                const SizedBox(height: 12),
                _buildFeatures(),

                const SizedBox(height: 24),

                // ── Technology Stack ──────────────────────────────
                _sectionLabel('Technology Stack'),
                const SizedBox(height: 12),
                _buildTechStack(),

                const SizedBox(height: 24),

                // ── Development Team ──────────────────────────────
                _sectionLabel('Development Team'),
                const SizedBox(height: 12),
                _buildTeamCard(),

                const SizedBox(height: 28),

                // ── Footer ────────────────────────────────────────
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── App hero — logo + name + version badge ──────────────────────────────────
  Widget _buildHero() {
    return Center(
      child: Column(
        children: [
          // Logo placeholder (uses icon if asset unavailable)
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/images/proport_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.school_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(children: [
              TextSpan(
                text: 'Grad',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              TextSpan(
                text: 'Port',
                style: GoogleFonts.poppins(
                  fontSize: 26,
                  fontWeight: FontWeight.w400,
                  color: AppColors.neutral,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25)),
            ),
            child: Text(
              'Version 2.0.0',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mission & Vision card ────────────────────────────────────────────────────
  Widget _buildMissionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About the App',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'GradPort is a mobile portfolio tracker designed for CICS students. It helps students organise their academic documents, track career milestones, and generate professional portfolios — all from their smartphones.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.65,
            ),
          ),
          const Divider(height: 24, color: AppColors.divider),

          // Mission
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.flag_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Mission',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Our mission is to provide students with a secure and easy-to-use mobile application for organizing academic documents and generating academic portfolios.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Vision
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.visibility_rounded,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vision',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'To become a trusted digital portfolio platform that helps CICS students manage their academic records and generate academic portfolios with ease.',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Key Features ─────────────────────────────────────────────────────────────
  Widget _buildFeatures() {
    const features = [
      _Feature(
        icon: Icons.folder_copy_rounded,
        title: 'Document Management',
        description:
            'Organise and store academic files by category — certificates, accomplishments, and more.',
        color: AppColors.primary,
      ),
      _Feature(
        icon: Icons.auto_awesome_rounded,
        title: 'Portfolio Generation',
        description:
            'Automatically compile your documents into a professional PDF or DOCX portfolio.',
        color: Color(0xFF7B2D8B),
      ),
      _Feature(
        icon: Icons.document_scanner_rounded,
        title: 'OCR Scanning',
        description:
            'Extract text from scanned documents using Google ML Kit Optical Character Recognition.',
        color: Color(0xFF0288D1),
      ),
      _Feature(
        icon: Icons.person_rounded,
        title: 'Profile Management',
        description:
            'Maintain your academic profile with name, program, year level, and school details.',
        color: Color(0xFF388E3C),
      ),
     
      _Feature(
        icon: Icons.track_changes_rounded,
        title: 'Career Tracking',
        description:
            'Monitor your academic milestones and progress across all portfolio sections.',
        color: Color(0xFFD32F2F),
      ),
    ];

    return Column(
      children: features
          .map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InfoCard(
                  icon: f.icon,
                  title: f.title,
                  description: f.description,
                  iconColor: f.color,
                ),
              ))
          .toList(),
    );
  }

  // ── Technology Stack ──────────────────────────────────────────────────────────
  Widget _buildTechStack() {
    const techs = [
      _Tech(label: 'Flutter',          color: Color(0xFF0553B1)),
      _Tech(label: 'MongoDB',          color: Color(0xFF116149)),
      _Tech(label: 'Node.js',          color: Color(0xFF417E38)),
      _Tech(label: 'Google ML Kit',    color: Color(0xFF1A73E8)),
      _Tech(label: 'Gemini API',       color: Color(0xFF7B2D8B)),
      _Tech(label: 'Firebase',         color: Color(0xFFF57C00)),
      _Tech(label: 'Dart',             color: Color(0xFF00B4D8)),
      _Tech(label: 'REST API',         color: Color(0xFF546E7A)),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: techs
            .map((t) => TechPill(label: t.label, color: t.color))
            .toList(),
      ),
    );
  }

  // ── Development Team card ─────────────────────────────────────────────────────
  Widget _buildTeamCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'Capstone Development Team',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'GradPort was developed as a capstone project by BSIT students dedicated to making career portfolio tracker accessible for every CICS students.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textSecondary,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Academic Year 2025–2026',
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Column(
      children: [
        const Divider(color: AppColors.divider),
        const SizedBox(height: 12),
        Text(
          '© 2025–2026 GradPort. All rights reserved.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Privacy Notice: All data is handled in accordance with applicable privacy laws. In development mode, data is stored locally and not transmitted to any server.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: AppColors.textMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _Feature {
  const _Feature({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String description;
  final Color color;
}

class _Tech {
  const _Tech({required this.label, required this.color});
  final String label;
  final Color color;
}