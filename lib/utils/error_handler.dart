import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';

class ErrorHandler {
  static void showError(BuildContext context, dynamic error, {String? customMessage}) {
    HapticFeedback.heavyImpact();
    
    final errorMessage = customMessage ?? _getErrorMessage(error);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                errorMessage,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static String _mapRetryableFetch(dynamic error) {
    final s = error.toString().toLowerCase();
    if (s.contains('authretryablefetchexception') || s.contains('retryable fetch') || s.contains('failed to fetch')) {
      return 'Temporary sign-in issue. Please try again in a moment.';
    }
    return '';
  }

  static void showSuccess(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static void showWarning(BuildContext context, String message) {
    HapticFeedback.selectionClick();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.warning_amber_outlined,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  static String _getErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    final retryableMsg = _mapRetryableFetch(error);
    if (retryableMsg.isNotEmpty) {
      return retryableMsg;
    }
    
    // Authentication errors
    if (errorString.contains('invalid login credentials') ||
        errorString.contains('invalid email or password')) {
      return 'Invalid email or password. Please check your credentials and try again.';
    }
    
    if (errorString.contains('email already registered') ||
        errorString.contains('user already registered')) {
      return 'This email is already registered. Please use a different email or try logging in.';
    }
    
    if (errorString.contains('weak password') ||
        errorString.contains('password should be at least')) {
      return 'Password is too weak. Please use at least 8 characters with a mix of letters, numbers, and symbols.';
    }
    
    if (errorString.contains('invalid email')) {
      return 'Please enter a valid email address.';
    }
    
    if (errorString.contains('email not confirmed')) {
      return 'Please check your email and click the verification link before logging in.';
    }
    
    if (errorString.contains('too many requests')) {
      return 'Too many attempts. Please wait a few minutes before trying again.';
    }
    
    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network error. Please check your internet connection and try again.';
    }
    
    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    }
    
    if (errorString.contains('username') && errorString.contains('taken')) {
      return 'This username is already taken. Please choose a different username.';
    }
    
    if (errorString.contains('server error') || errorString.contains('500')) {
      return 'Server error. Please try again in a few moments.';
    }
    
    if (errorString.contains('unauthorized') || errorString.contains('401')) {
      return 'Session expired. Please log in again.';
    }
    
    if (errorString.contains('forbidden') || errorString.contains('403')) {
      return 'Access denied. Please check your permissions.';
    }
    
    if (errorString.contains('not found') || errorString.contains('404')) {
      return 'Resource not found. Please try again.';
    }
    
    // Generic fallback
    return 'Something went wrong. Please try again.';
  }

  static void showLoadingDialog(BuildContext context, {String message = 'Loading...'}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static void hideLoadingDialog(BuildContext context) {
    Navigator.of(context, rootNavigator: true).pop();
  }

  static Future<bool> showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 14,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              cancelText,
              style: const TextStyle(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              confirmText,
              style: TextStyle(
                color: isDestructive ? AppColors.error : AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    
    return result ?? false;
  }
}