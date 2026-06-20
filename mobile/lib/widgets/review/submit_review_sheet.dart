import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/text_styles.dart';
import '../../models/review.dart';
import '../../providers/auth_provider.dart';
import '../../providers/provider_provider.dart';
import '../common/app_button.dart';
import '../common/app_text_field.dart';

class SubmitReviewSheet extends StatefulWidget {
  final String providerId;
  final VoidCallback? onSubmitted;

  const SubmitReviewSheet({
    super.key,
    required this.providerId,
    this.onSubmitted,
  });

  @override
  State<SubmitReviewSheet> createState() => _SubmitReviewSheetState();
}

class _SubmitReviewSheetState extends State<SubmitReviewSheet> {
  int _selectedRating = 0;
  final _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedRating < 1) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    if (user == null) return;

    final providerProvider =
        Provider.of<ProviderProvider>(context, listen: false);
    final review = Review(
      id: const Uuid().v4(),
      providerId: widget.providerId,
      userId: user.id,
      userName: user.name ?? 'Utilisateur',
      rating: _selectedRating,
      text: _textController.text.trim(),
      createdAt: DateTime.now(),
    );

    providerProvider.addReviewLocally(review);
    widget.onSubmitted?.call();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Merci pour votre avis'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppTheme.spacingL),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Donner mon avis',
            style: AppTextStyles.titleLarge.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppTheme.spacingM),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starIndex = index + 1;
              return IconButton(
                onPressed: () {
                  setState(() => _selectedRating = starIndex);
                },
                icon: Icon(
                  starIndex <= _selectedRating ? Icons.star : Icons.star_border,
                  size: 40,
                  color: Colors.amber,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4),
              );
            }),
          ),
          const SizedBox(height: AppTheme.spacingM),
          AppTextField(
            hint: 'Votre avis (optionnel)',
            controller: _textController,
            maxLines: 4,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: AppTheme.spacingL),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Annuler'),
                ),
              ),
              const SizedBox(width: AppTheme.spacingM),
              Expanded(
                child: AppButton(
                  text: 'Publier',
                  onPressed: _selectedRating >= 1 ? _submit : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
