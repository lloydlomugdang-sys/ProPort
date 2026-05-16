import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'add_certificate_screen.dart';
import 'certificate_view_screen.dart';
import 'edit_certificate_screen.dart';

class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  final List<Map<String, String>> certificates = [
    {
      'title': 'Career Readiness Certificate',
      'date': 'May 8, 2026',
      'link': 'certificate-link.com',
      'description': 'Certificate for completing career readiness activities.',
    },
    {
      'title': 'Flutter Basics Certificate',
      'date': 'May 9, 2026',
      'link': 'flutter-certificate.com',
      'description': 'Certificate for learning Flutter mobile app basics.',
    },
    {
      'title': 'Portfolio Workshop Certificate',
      'date': 'May 10, 2026',
      'link': 'portfolio-workshop.com',
      'description': 'Certificate for joining a portfolio building workshop.',
    },
  ];

  Future<void> goToAddCertificate() async {
    final newCertificate = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddCertificateScreen(),
      ),
    );

    if (!mounted) return;

    if (newCertificate != null) {
      setState(() {
        certificates.add(newCertificate);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate added successfully.'),
        ),
      );
    }
  }

  Future<void> goToEditCertificate(int index) async {
    final certificate = certificates[index];

    final updatedCertificate = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCertificateScreen(
          initialTitle: certificate['title']!,
          initialDate: certificate['date']!,
          initialLink: certificate['link']!,
          initialDescription: certificate['description']!,
        ),
      ),
    );

    if (!mounted) return;

    if (updatedCertificate != null) {
      setState(() {
        certificates[index] = updatedCertificate;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate updated successfully.'),
        ),
      );
    }
  }

  Future<void> goToViewCertificate(int index) async {
    final certificate = certificates[index];

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => CertificateViewScreen(
          title: certificate['title']!,
          date: certificate['date']!,
          link: certificate['link']!,
          description: certificate['description']!,
        ),
      ),
    );

    if (!mounted || result == null) return;

    if (result['action'] == 'delete') {
      setState(() {
        certificates.removeAt(index);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate deleted.'),
        ),
      );
    }

    if (result['action'] == 'update') {
      final updatedCertificate = result['certificate'] as Map<String, String>;

      setState(() {
        certificates[index] = updatedCertificate;
      });
    }
  }

  void deleteCertificate(int index) {
    setState(() {
      certificates.removeAt(index);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Certificate deleted.'),
      ),
    );
  }

  Widget _certificateCard(int index) {
    final certificate = certificates[index];

    return InkWell(
      onTap: () {
        goToViewCertificate(index);
      },
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 92,
              height: 76,
              decoration: BoxDecoration(
                color: const Color(0xFF587A80),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.badge_outlined,
                color: AppColors.white,
                size: 34,
              ),
            ),

            const SizedBox(width: 14),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    certificate['title']!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    certificate['date']!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 10),

                  Row(
                    children: [
                      SizedBox(
                        height: 30,
                        child: ElevatedButton(
                          onPressed: () {
                            goToEditCertificate(index);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.input,
                            foregroundColor: AppColors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Edit',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 30,
                        child: OutlinedButton(
                          onPressed: () {
                            deleteCertificate(index);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Delete',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        onPressed: goToAddCertificate,
        backgroundColor: AppColors.input,
        foregroundColor: AppColors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 90),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Certificates',
                      style: TextStyle(
                        color: AppColors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              const Text(
                'Certificate List',
                style: TextStyle(
                  color: AppColors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 14),

              if (certificates.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Text(
                    'No certificates yet. Tap the + button to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              else
                ...List.generate(
                  certificates.length,
                  (index) => _certificateCard(index),
                ),
            ],
          ),
        ),
      ),
    );
  }
}