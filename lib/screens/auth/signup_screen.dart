import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../../services/auth_service.dart';
import '../../config/app_colors.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../utils/error_handler.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'login_screen.dart';
import '../../services/localization_service.dart';
import '../../services/referral_service.dart';
import '../../services/preferences_service.dart';
import '../legal/terms_of_service_screen.dart' as TermsScreen;
import '../legal/privacy_policy_screen.dart' as PrivacyScreen;
import '../../services/location_service.dart';

class SignupScreen extends StatefulWidget {
  final DateTime? dateOfBirth;
  const SignupScreen({super.key, this.dateOfBirth});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _referralCodeController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreeToTerms = false;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
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

    // Username availability checker
    _usernameController.addListener(_checkUsernameAvailability);

    // Prefill referral code if captured from a deep link
    PreferencesService().getPendingReferralCode().then((code) {
      if (code != null && code.isNotEmpty) {
        _referralCodeController.text = code;
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _referralCodeController.dispose();
    super.dispose();
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();
    if (username.length < 3) return;

    setState(() => _isCheckingUsername = true);

    try {
      final isAvailable = await _authService.isUsernameAvailable(username);
      if (mounted) {
        setState(() {
          _isUsernameAvailable = isAvailable;
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
        });
      }
    }
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreeToTerms) {
      ErrorHandler.showWarning(
        context,
        LocalizationService.t('agree_terms_privacy_warning'),
      );
      return;
    }

    setState(() => _isLoading = true);
    HapticFeedback.lightImpact();

    try {
      await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim().toLowerCase(),
        dateOfBirth: widget.dateOfBirth,
      );

      if (mounted) {
        HapticFeedback.lightImpact();

        // Show success message
        ErrorHandler.showSuccess(
          context,
          LocalizationService.t('account_created_check_email_success'),
        );

        // Apply referral code if provided
        final code = _referralCodeController.text.trim();
        if (code.isNotEmpty) {
          try {
            final ok = await ReferralService().claimReferral(code);
            if (ok) {
              ErrorHandler.showSuccess(
                context,
                LocalizationService.t('referral_claim_success'),
              );
              // Clear pending referral code after successful claim
              await PreferencesService().clearPendingReferralCode();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(LocalizationService.t('referral_claim_failed')),
                  backgroundColor: AppColors.error,
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(LocalizationService.t('referral_claim_failed')),
                backgroundColor: AppColors.error,
              ),
            );
          }
        }

        // One-time location consent prompt (strict policy)
        final locationService = LocationService();
        final consent = await locationService.getConsentChoice();
        if (consent == null) {
          await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(LocalizationService.t('allow_location')),
              content: Text(
                LocalizationService.t(
                  'to_improve_your_local_feed_allow_location_access',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    await locationService.setConsentChoice(false);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  },
                  child: Text(LocalizationService.t('no_thanks')),
                ),
                TextButton(
                  onPressed: () async {
                    await locationService.setConsentChoice(true);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    // Attempt to store country/city now
                    await locationService.updateUserProfileLocation();
                  },
                  child: Text(LocalizationService.t('allow')),
                ),
              ],
            ),
          );
        }

        // Navigate to login screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                  const SizedBox(height: 20),

                  // Logo and Title
                  Center(
                    child: Column(
                      children: [
                        SvgPicture.asset(
                          'assets/icons/app_icon.svg',
                          width: 80,
                          height: 80,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          LocalizationService.t('signup_subtitle'),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Signup Form
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        CustomTextField(
                          controller: _fullNameController,
                          label: LocalizationService.t('full_name'),
                          hint: LocalizationService.t('enter_full_name'),
                          prefixIcon: Icons.person_outline,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return LocalizationService.t(
                                'please_enter_full_name',
                              );
                            }
                            if (value.length < 2) {
                              return LocalizationService.t('name_min_length');
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        CustomTextField(
                          controller: _usernameController,
                          label: LocalizationService.t('username'),
                          hint: LocalizationService.t('choose_username'),
                          prefixIcon: Icons.alternate_email,
                          suffixIcon: _isCheckingUsername
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : _usernameController.text.length >= 3
                              ? Icon(
                                  _isUsernameAvailable
                                      ? Icons.check_circle
                                      : Icons.error,
                                  color: _isUsernameAvailable
                                      ? AppColors.success
                                      : AppColors.error,
                                )
                              : null,
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return LocalizationService.t(
                                'please_enter_username',
                              );
                            }
                            if (value.length < 3) {
                              return LocalizationService.t(
                                'username_min_length',
                              );
                            }
                            if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(value)) {
                              return LocalizationService.t('username_invalid');
                            }
                            if (!_isUsernameAvailable) {
                              return LocalizationService.t('username_taken');
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

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

                        const SizedBox(height: 20),

                        CustomTextField(
                          controller: _passwordController,
                          label: LocalizationService.t('password'),
                          hint: LocalizationService.t('create_strong_password'),
                          obscureText: _obscurePassword,
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return LocalizationService.t(
                                'please_enter_password',
                              );
                            }
                            if (value.length < 8) {
                              return LocalizationService.t(
                                'password_min_length_8',
                              );
                            }
                            if (!RegExp(
                              r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)',
                            ).hasMatch(value)) {
                              return LocalizationService.t(
                                'password_requirements',
                              );
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 20),

                        CustomTextField(
                          controller: _confirmPasswordController,
                          label: LocalizationService.t('confirm_password'),
                          hint: LocalizationService.t('confirm_your_password'),
                          obscureText: _obscureConfirmPassword,
                          prefixIcon: Icons.lock_outline,
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword;
                              });
                            },
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return LocalizationService.t(
                                'please_confirm_password',
                              );
                            }
                            if (value != _passwordController.text) {
                              return LocalizationService.t(
                                'passwords_do_not_match',
                              );
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 24),

                        // Optional Referral Code
                        CustomTextField(
                          controller: _referralCodeController,
                          label: LocalizationService.t(
                            'referral_code_optional',
                          ),
                          hint: LocalizationService.t('enter_referral_code'),
                          prefixIcon: Icons.card_giftcard,
                          validator: (value) {
                            // Optional field; always valid
                            return null;
                          },
                        ),

                        // Terms and Conditions
                        Row(
                          children: [
                            Checkbox(
                              value: _agreeToTerms,
                              onChanged: (value) {
                                setState(() {
                                  _agreeToTerms = value ?? false;
                                });
                              },
                              activeColor: AppColors.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                  ),
                                  children: [
                                    TextSpan(
                                      text:
                                          LocalizationService.t('agree_to') +
                                          ' ',
                                    ),
                                    TextSpan(
                                      text: LocalizationService.t(
                                        'terms_of_service',
                                      ),
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      recognizer: (TapGestureRecognizer()
                                        ..onTap = () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const TermsScreen.TermsOfServiceScreen(),
                                            ),
                                          );
                                        }),
                                    ),
                                    TextSpan(
                                      text:
                                          ' ' +
                                          LocalizationService.t('and_word') +
                                          ' ',
                                    ),
                                    TextSpan(
                                      text: LocalizationService.t(
                                        'privacy_policy',
                                      ),
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      recognizer: (TapGestureRecognizer()
                                        ..onTap = () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  const PrivacyScreen.PrivacyPolicyScreen(),
                                            ),
                                          );
                                        }),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Signup Button
                        CustomButton(
                          text: LocalizationService.t('create_account'),
                          onPressed: _handleSignup,
                          isLoading: _isLoading,
                          width: double.infinity,
                        ),

                        const SizedBox(height: 32),

                        // Divider
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.border,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                LocalizationService.t('or'),
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: AppColors.border,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Login Link
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              LocalizationService.t('already_have_account') +
                                  ' ',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 16,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const LoginScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                LocalizationService.t('sign_in'),
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
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
          ),
        ),
      ),
    );
  }
}
