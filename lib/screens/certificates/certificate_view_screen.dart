import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import 'edit_certificate_screen.dart';

class CertificateViewScreen extends StatefulWidget {
  final String title;
  final String date;
  final String link;
  final String description;

  const CertificateViewScreen({
    super.key,
    required this.title,
    required this.date,
    required this.link,
    required this.description,
  });

  @override
  State<CertificateViewScreen> createState() => _CertificateViewScreenState();
}

class _CertificateViewScreenState extends State<CertificateViewScreen> {
  late String certificateTitle;
  late String certificateDate;
  late String certificateLink;
  late String certificateDescription;

  @override
  void initState() {
    super.initState();

    certificateTitle = widget.title;
    certificateDate = widget.date;
    certificateLink = widget.link;
    certificateDescription = widget.description;
  }

  Map<String, String> get currentCertificate {
    return {
      'title': certificateTitle,
      'date': certificateDate,
      'link': certificateLink,
      'description': certificateDescription,
    };
  }

  Future<void> goToEditCertificate() async {
    final updatedCertificate = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(
        builder: (_) => EditCertificateScreen(
          initialTitle: certificateTitle,
          initialDate: certificateDate,
          initialLink: certificateLink,
          initialDescription: certificateDescription,
        ),
      ),
    );

    if (updatedCertificate != null) {
      setState(() {
        certificateTitle = updatedCertificate['title']!;
        certificateDate = updatedCertificate['date']!;
        certificateLink = updatedCertificate['link']!;
        certificateDescription = updatedCertificate['description']!;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Certificate updated successfully.'),
        ),
      );
    }
  }

  void deleteCertificate() {
    Navigator.pop(context, {
      'action': 'delete',
    });
  }

  void goBack() {
    Navigator.pop(context, {
      'action': 'update',
      'certificate': currentCertificate,
    });
  }

  Widget _previewImage() {
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: const Color(0xFF587A80),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: const Icon(
        Icons.badge_outlined,
        color: AppColors.white,
        size: 64,
      ),
    );
  }

  Widget _detailItem({
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.white,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailsBox() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Certificate.png',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 18),

          _detailItem(
            label: 'Certificate Title',
            value: certificateTitle,
          ),

          _detailItem(
            label: 'Date',
            value: certificateDate,
          ),

          _detailItem(
            label: 'Description',
            value: certificateDescription,
          ),

          _detailItem(
            label: 'Certificate Link',
            value: certificateLink,
          ),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        SizedBox(
          height: 36,
          child: ElevatedButton(
            onPressed: goToEditCertificate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Edit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 36,
          child: OutlinedButton(
            onPressed: deleteCertificate,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'Delete',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: goBack,
                    icon: const Icon(
                      Icons.arrow_back_ios_new,
                      color: AppColors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'Certificate View',
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

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _previewImage(),

                    const SizedBox(height: 16),

                    _detailsBox(),

                    const SizedBox(height: 14),

                    _actionButtons(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}