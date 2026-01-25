import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/auth_service.dart';
import '../../services/app_service.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/error_handler.dart';
import 'login_screen.dart';
import 'update_password_screen.dart'; // Add this import

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>(); // New key for OTP form
  final _emailController = TextEditingController();
  final _otpController = TextEditingController(); // New controller for OTP
  final _authService = AuthService();

  bool _isLoading = false;
  bool _emailSent = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.3, 1.0, curve: Curves.easeOut),
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleResetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await _authService.resetPassword(_emailController.text.trim());

      if (mounted) {
        HapticFeedback.lightImpact();
        setState(() {
          _emailSent = true;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, e);
        setState(() => _isLoading = false);
      }
    }
  }

  // New method to handle OTP verification
  Future<void> _handleVerifyOtp() async {
    if (!_otpFormKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      // Set recovery mode to prevent auto-navigation to home upon auth success
      AppService().setRecoveryInProgress(true);

      await _authService.verifyOtp(
        email: _emailController.text.trim(),
        token: _otpController.text.trim(),
      );

      // Manual navigation to ensure UI doesn't hang waiting for state stream
      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UpdatePasswordScreen()),
        );
      }
    } catch (e) {
      // Reset recovery flag on failure
      AppService().setRecoveryInProgress(false);

      if (mounted) {
        ErrorHandler.showError(context, e);
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),

                  // Header
                  Center(
                    child: Column(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.border,
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _emailSent
                                ? Icons.mark_email_read
                                : Icons.lock_reset,
                            color: AppColors.primary,
                            size: 40,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          _emailSent
                              ? LocalizationService.t(
                                  'enter_verification_code',
                                ) // Update translation key if needed
                              : LocalizationService.t('forgot_password_title'),
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _emailSent
                              ? '${LocalizationService.t('email_sent_message')} ${_emailController.text}'
                              : LocalizationService.t(
                                  'forgot_password_subtitle',
                                ),
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 48),

                  if (!_emailSent) ...[
                    // Reset Form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          CustomTextField(
                            controller: _emailController,
                            label: LocalizationService.t('email'),
                            hint: LocalizationService.t('enter_email'),
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.email_outlined,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return LocalizationService.t(
                                  'please_enter_email',
                                );
                              }
                              if (!RegExp(
                                r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
                              ).hasMatch(value)) {
                                return LocalizationService.t('invalid_email');
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          // Reset Button
                          CustomButton(
                            text: LocalizationService.t('send_reset_link'),
                            onPressed: _handleResetPassword,
                            isLoading: _isLoading,
                            width: double.infinity,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // OTP Verification Form
                    Form(
                      key: _otpFormKey,
                      child: Column(
                        children: [
                          CustomTextField(
                            controller: _otpController,
                            label: LocalizationService.t('verification_code'),
                            hint: LocalizationService.t('enter_6_digit_code'),
                            keyboardType: TextInputType.number,
                            prefixIcon: Icons.lock_outline,
                            maxLength: 6,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return LocalizationService.t(
                                  'please_enter_code',
                                );
                              }
                              if (value.length != 6) {
                                return LocalizationService.t(
                                  'code_must_be_6_digits',
                                );
                              }
                              return null;
                            },
                          ),

                          const SizedBox(height: 32),

                          // Verify Button
                          CustomButton(
                            text: LocalizationService.t('verify_code'),
                            onPressed: _handleVerifyOtp,
                            isLoading: _isLoading,
                            width: double.infinity,
                          ),

                          const SizedBox(height: 24),

                          // Resend Button
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _emailSent = false;
                                _otpController.clear();
                              });
                            },
                            child: Text(
                              LocalizationService.t('resend_email_link'),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 48),

                  // Back to Login
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      },
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      label: Text(
                        LocalizationService.t('back_to_sign_in'),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
