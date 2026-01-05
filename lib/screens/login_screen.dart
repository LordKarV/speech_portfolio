import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:speech_app/theme/app_button_styles.dart';
import 'dart:developer' as developer;
import '../theme/app_colors.dart';
import '../theme/app_dimensions.dart';
import '../components/app_label.dart';
import '../components/app_card.dart';

/// Authentication screen for user login and registration
/// Supports email/password authentication and Google Sign-In
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {

  bool isLogin = true;
  bool showForgotPassword = false;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();

  /// Handle form submission for login or registration
  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    developer.log('🔐 AuthScreen: Starting ${isLogin ? 'login' : 'registration'} process');
    developer.log('📧 AuthScreen: Email: $email');

    try {
      if (isLogin) {

        developer.log('🔑 AuthScreen: Attempting login with email/password');
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        developer.log('✅ AuthScreen: Login successful');
      } else {

        developer.log('📝 AuthScreen: Attempting registration with email/password');
        developer.log('👤 AuthScreen: Name: $name');

        final userCred = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        developer.log('💾 AuthScreen: Creating user document in Firestore');
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .set({
          'name': name,
          'email': email,
          'createdAt': Timestamp.now(),
        });

        developer.log('✅ AuthScreen: Registration and user document creation successful');
      }
    } catch (e) {
      developer.log('❌ AuthScreen: Authentication error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Authentication failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Handle Google Sign-In authentication
  Future<void> _signInWithGoogle() async {
    try {
      developer.log('🔐 AuthScreen: Starting Google Sign-In process');

      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        developer.log('⚠️ AuthScreen: Google Sign-In cancelled by user');
        return;
      }

      developer.log('🔑 AuthScreen: Getting Google authentication credentials');
      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      developer.log('🔐 AuthScreen: Signing in with Google credentials');
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential);

      // Create user document for new Google users
      if (userCred.additionalUserInfo!.isNewUser) {
        developer.log('👤 AuthScreen: New Google user detected, creating user document');
        developer.log('📧 AuthScreen: Google user email: ${userCred.user!.email}');
        developer.log('👤 AuthScreen: Google user name: ${userCred.user!.displayName}');

        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .set({
          'name': userCred.user!.displayName ?? '',
          'email': userCred.user!.email,
          'createdAt': Timestamp.now(),
          'provider': 'google',
        });

        developer.log('✅ AuthScreen: Google user document created successfully');
      } else {
        developer.log('✅ AuthScreen: Existing Google user signed in successfully');
      }
    } catch (e) {
      developer.log('❌ AuthScreen: Google sign-in error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailController.text.trim();

    if (email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please enter your email address first'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    developer.log('🔐 AuthScreen: Sending password reset email to: $email');

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      developer.log('✅ AuthScreen: Password reset email sent successfully');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Password reset email sent to $email'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {
          showForgotPassword = false;
        });
      }
    } catch (e) {
      developer.log('❌ AuthScreen: Password reset error: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send reset email: ${e.toString()}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _toggleAuthMode() {
    developer.log('🔄 AuthScreen: Toggling auth mode from ${isLogin ? 'login' : 'registration'} to ${!isLogin ? 'login' : 'registration'}');
    setState(() {
      isLogin = !isLogin;
      showForgotPassword = false;
    });
  }

  void _toggleForgotPassword() {
    developer.log('🔄 AuthScreen: Toggling forgot password view');
    setState(() {
      showForgotPassword = !showForgotPassword;
    });
  }

  @override
  void dispose() {
    developer.log('🗑️ AuthScreen: Disposing controllers');
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    developer.log('🎨 AuthScreen: Building UI in ${isLogin ? 'login' : 'registration'} mode');

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingXLarge),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(AppDimensions.radiusXLarge),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withOpacity(0.3),
                        blurRadius: 30,
                        spreadRadius: 0,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    size: 60,
                    color: Colors.white,
                  ),
                ),

                const SizedBox(height: AppDimensions.marginXXLarge),

                AppLabel.primary(
                  isLogin ? 'Welcome Back!' : 'Create Account',
                  size: LabelSize.xlarge,
                  fontWeight: FontWeight.bold,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppDimensions.marginSmall),

                AppLabel.secondary(
                  isLogin 
                      ? 'Sign in to continue analyzing your speech'
                      : 'Join us to start your speech analysis journey',
                  size: LabelSize.medium,
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: AppDimensions.marginXXLarge),

                AppCard.elevated(
                  padding: const EdgeInsets.all(AppDimensions.paddingXXLarge),
                  child: showForgotPassword 
                      ? _buildForgotPasswordForm()
                      : _buildAuthForm(),
                ),

                const SizedBox(height: AppDimensions.marginXLarge),

                if (!showForgotPassword)
                  TextButton(
                    onPressed: _toggleAuthMode,
                    style: AppButtonStyles.textButton,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 16,
                        ),
                        children: [
                          TextSpan(text: isLogin ? "Don't have an account? " : "Already have an account? "),
                          TextSpan(
                            text: isLogin ? "Sign up" : "Sign in",
                            style: const TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isLogin && !showForgotPassword) ...[
                  const SizedBox(height: AppDimensions.marginMedium),
                  TextButton(
                    onPressed: _toggleForgotPassword,
                    style: AppButtonStyles.textButton,
                    child: const Text(
                      'Forgot your password?',
                      style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAuthForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        if (!isLogin) ...[
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: 'Full Name',
              prefixIcon: const Icon(Icons.person_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),
          const SizedBox(height: AppDimensions.marginLarge),
        ],

        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: const Icon(Icons.email_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.marginLarge),

        TextField(
          controller: _passwordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.marginXXLarge),

        ElevatedButton(
          onPressed: _submit,
          style: AppButtonStyles.primaryButton,
          child: Text(isLogin ? 'Sign In' : 'Create Account'),
        ),

        const SizedBox(height: AppDimensions.marginLarge),

        Row(
          children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppDimensions.paddingMedium),
              child: AppLabel.secondary('or', size: LabelSize.small),
            ),
            const Expanded(child: Divider()),
          ],
        ),

        const SizedBox(height: AppDimensions.marginLarge),

        ElevatedButton.icon(
          onPressed: _signInWithGoogle,
          style: AppButtonStyles.secondaryButton,
          icon: const Icon(Icons.login_rounded),
          label: const Text('Continue with Google'),
        ),
      ],
    );
  }

  Widget _buildForgotPasswordForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [

        Row(
          children: [
            IconButton(
              onPressed: _toggleForgotPassword,
              icon: const Icon(Icons.arrow_back_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.backgroundTertiary,
                foregroundColor: AppColors.textSecondary,
              ),
            ),
            const SizedBox(width: AppDimensions.marginMedium),
            Expanded(
              child: AppLabel.primary(
                'Reset Password',
                size: LabelSize.large,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        const SizedBox(height: AppDimensions.marginXLarge),

        Container(
          padding: const EdgeInsets.all(AppDimensions.paddingLarge),
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            border: Border.all(
              color: AppColors.accent.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: AppDimensions.marginMedium),
              Expanded(
                child: AppLabel.secondary(
                  'Enter your email address and we\'ll send you a link to reset your password.',
                  size: LabelSize.small,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppDimensions.marginXLarge),

        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: const Icon(Icons.email_rounded),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusLarge),
              borderSide: const BorderSide(color: AppColors.accent, width: 2),
            ),
          ),
        ),

        const SizedBox(height: AppDimensions.marginXXLarge),

        ElevatedButton(
          onPressed: _handleForgotPassword,
          style: AppButtonStyles.primaryButton,
          child: const Text('Send Reset Email'),
        ),

        const SizedBox(height: AppDimensions.marginLarge),

        TextButton(
          onPressed: _toggleForgotPassword,
          style: AppButtonStyles.textButton,
          child: const Text('Back to Sign In'),
        ),
      ],
    );
  }
}
