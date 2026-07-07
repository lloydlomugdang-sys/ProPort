// LOCATION: lib/screens/settings/help_center_screen.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../constants/app_colors.dart';
import '../../widgets/grad_app_bar.dart';
import '../../widgets/search_bar_field.dart';
import 'widgets/faq_card.dart';

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchCtrl = TextEditingController();
  String _query        = '';
  String _selectedCat  = 'All';

  static const List<String> _categories = [
    'All', 'Account', 'Files', 'Portfolio', 'OCR', 'General',
  ];

  // ─── FAQ data ─────────────────────────────────────────────────────────────
  static const List<_Faq> _faqs = [
    _Faq(
      category: 'Account',
      question: 'How do I update my profile information?',
      answer:
          'Go to the Profile tab at the bottom of the screen, then tap the edit icon in the top-right corner. You can update your Full Name, Email, Program, Year Level, and School. Tap "Save Changes" when done.',
    ),
    _Faq(
      category: 'Account',
      question: 'How do I change my password?',
      answer:
          'Navigate to Settings → Change Password. Enter your current password, then your new password twice. Your new password must be at least 8 characters long.',
    ),
    _Faq(
      category: 'Files',
      question: 'What file types are supported for upload?',
      answer:
          'GradPort currently supports PDF, JPG, JPEG, DOCX and PNG files. Additional file formats will be added in future updates.',
    ),
    _Faq(
      category: 'Files',
      question: 'How do I organise my uploaded files?',
      answer:
          'When adding a file, select a Content Type (e.g. Certificates, Accomplishments) and a Folder within that category. Your files are then automatically sorted and displayed in the Files screen.',
    ),
    _Faq(
      category: 'Files',
      question: 'Can I delete a file after uploading it?',
      answer:
          'Yes. Open the Files tab, navigate to the folder containing the file, and tap the ⋮ menu on the right side of the file row. Select Delete to remove the file.',
    ),
    _Faq(
      category: 'Portfolio',
      question: 'How do I generate my portfolio?',
      answer:
          'From the Dashboard, tap "Generate Portfolio". Fill in your portfolio information (name, year, section, instructor, etc.), review the Portfolio Summary, then choose your export format (PDF or DOCX) on the Export screen.',
    ),
    _Faq(
      category: 'Portfolio',
      question: 'What sections are included in the portfolio?',
      answer:
          'The portfolio includes Creative Title, Curriculum Vitae, Scholastic Record, Certificates, Accomplishments, Other Achievements, and College Report — matching the standard GradPort document structure.',
    ),
    _Faq(
      category: 'OCR',
      question: 'What is OCR and how does it work in GradPort?',
      answer:
          'OCR (Optical Character Recognition) lets GradPort automatically extract text from scanned documents and images. OCR is powered by Google ML Kit.',
    ),
    _Faq(
      category: 'OCR',
      question: 'Which documents work best with OCR scanning?',
      answer:
          'Clear, well-lit photographs or scans of printed text work best. Handwritten documents may have lower accuracy. Ensure the document is flat and fully in frame before scanning.',
    ),
    _Faq(
      category: 'General',
      question: 'Is my data saved to the cloud?',
      answer:
          'GradPort is currently in development mode. Data is stored temporarily in local memory and will not persist between app restarts. Full cloud storage via MongoDB will be connected in a future release.',
    ),
    _Faq(
      category: 'General',
      question: 'How do I contact support?',
      answer:
          'You can reach the GradPort support team by emailing support@gradport.app. Include your app version and a description of the issue for the fastest response.',
    ),
  ];

  List<_Faq> get _filtered {
    var list = _faqs;
    if (_selectedCat != 'All') {
      list = list.where((f) => f.category == _selectedCat).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((f) =>
              f.question.toLowerCase().contains(q) ||
              f.answer.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const GradBackAppBar(title: 'Help Center'),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────
            Text(
              'How can we help you?',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Search or browse the topics below.',
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 16),

            // ── Search bar ────────────────────────────────────────
            SearchBarField(
              controller: _searchCtrl,
              hintText: 'Search help articles...',
              onChanged: (v) => setState(() => _query = v),
            ),

            const SizedBox(height: 16),

            // ── Category chips ────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final isSelected = cat == _selectedCat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () =>
                          setState(() => _selectedCat = cat),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.cardBorder,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          cat,
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? Colors.white
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // ── FAQ section label ─────────────────────────────────
            Text(
              filtered.isEmpty
                  ? 'No results found'
                  : 'Frequently Asked Questions',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 10),

            // ── FAQ cards ─────────────────────────────────────────
            ...filtered.map((faq) => FaqCard(
                  question: faq.question,
                  answer: faq.answer,
                )),

            const SizedBox(height: 24),

            // ── Contact support card ──────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: AppColors.primaryGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.support_agent_rounded,
                      color: Colors.white, size: 28),
                  const SizedBox(height: 10),
                  Text(
                    'Still need help?',
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Our support team is ready to assist you.',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.email_outlined,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'support@gradport.app',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── App version ───────────────────────────────────────
            Center(
              child: Text(
                'GradPort v2.0.0 • Build 2025',
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Faq {
  const _Faq({
    required this.category,
    required this.question,
    required this.answer,
  });
  final String category;
  final String question;
  final String answer;
}