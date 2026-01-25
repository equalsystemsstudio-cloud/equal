import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../config/app_colors.dart';
import '../../services/localization_service.dart';
import '../../widgets/custom_button.dart';
import 'signup_screen.dart';
import 'login_screen.dart';

class DateOfBirthScreen extends StatefulWidget {
  const DateOfBirthScreen({super.key});

  @override
  State<DateOfBirthScreen> createState() => _DateOfBirthScreenState();
}

class _DateOfBirthScreenState extends State<DateOfBirthScreen> {
  DateTime _selectedDate = DateTime.now().subtract(
    const Duration(days: 365 * 13),
  ); // Default to 13 years ago

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  void _handleNext() {
    final age = _calculateAge(_selectedDate);

    if (age < 13) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            LocalizationService.t('age_restriction_title') !=
                    'age_restriction_title'
                ? LocalizationService.t('age_restriction_title')
                : 'Age Restriction',
          ),
          content: Text(
            LocalizationService.t('age_restriction_message') !=
                    'age_restriction_message'
                ? LocalizationService.t('age_restriction_message')
                : 'You must be at least 13 years old to create an account.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SignupScreen(dateOfBirth: _selectedDate),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const LoginScreen()),
            );
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                LocalizationService.t('when_is_your_birthday') !=
                        'when_is_your_birthday'
                    ? LocalizationService.t('when_is_your_birthday')
                    : 'When is your birthday?',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                LocalizationService.t('birthday_description') !=
                        'birthday_description'
                    ? LocalizationService.t('birthday_description')
                    : 'We need your birthday to ensure you are eligible to use Equal. This will not be shown publicly.',
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 40),

              // Date Picker
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: CupertinoTheme(
                  data: const CupertinoThemeData(
                    textTheme: CupertinoTextThemeData(
                      dateTimePickerTextStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                      ),
                    ),
                  ),
                  child: CupertinoDatePicker(
                    mode: CupertinoDatePickerMode.date,
                    initialDateTime: _selectedDate,
                    maximumDate: DateTime.now(),
                    minimumDate: DateTime(1900),
                    onDateTimeChanged: (DateTime newDate) {
                      setState(() {
                        _selectedDate = newDate;
                      });
                    },
                  ),
                ),
              ),

              const Spacer(),

              CustomButton(
                text: LocalizationService.t('next') != 'next'
                    ? LocalizationService.t('next')
                    : 'Next',
                onPressed: _handleNext,
                isLoading: false,
                width: double.infinity,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
