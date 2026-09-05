import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/auth_session_controller.dart';
import '../data/auth_repository.dart';
import '../models/otp_challenge_response.dart';

class OtpScreen extends ConsumerStatefulWidget {
  final String challengeId;
  final String email;
  final OtpPurpose purpose;
  final int expiresInSeconds;

  const OtpScreen({
    super.key,
    required this.challengeId,
    required this.email,
    required this.purpose,
    this.expiresInSeconds = 600,
  });

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final TextEditingController _otpController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isLoading = false;

  late String _currentChallengeId;
  int _cooldownSeconds = 60;
  late int _expirySeconds;
  Timer? _cooldownTimer;
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _currentChallengeId = widget.challengeId;
    _expirySeconds = widget.expiresInSeconds;
    _startTimers();

    // Auto-focus on start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();
    _otpController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startTimers() {
    _cooldownTimer?.cancel();
    _expiryTimer?.cancel();

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldownSeconds <= 0) {
        timer.cancel();
      } else {
        if (mounted) {
          setState(() {
            _cooldownSeconds--;
          });
        }
      }
    });

    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_expirySeconds <= 0) {
        timer.cancel();
      } else {
        if (mounted) {
          setState(() {
            _expirySeconds--;
          });
        }
      }
    });
  }

  String _formatExpiryTime(int seconds) {
    if (seconds <= 0) return 'Expired';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _handleVerify() async {
    final otp = _otpController.text.trim();
    if (otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a complete 6-digit OTP code.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_expirySeconds <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This verification code has expired. Please request a new code.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(authRepositoryProvider);

      if (widget.purpose == OtpPurpose.register) {
        await repo.verifyRegistrationOtp(
          challengeId: _currentChallengeId,
          otp: otp,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email verified successfully! You can now log in with your credentials.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (widget.purpose == OtpPurpose.login) {
        await repo.verifyLoginOtp(
          challengeId: _currentChallengeId,
          otp: otp,
        );

        // Notify session controller to initialize fresh state and invalidate any old cached data
        ref.read(authSessionControllerProvider.notifier).onSessionStarted();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Login successful! Welcome to FreshTrack.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } else if (widget.purpose == OtpPurpose.verifyEmail) {
        await repo.verifyEmailVerificationOtp(
          challengeId: _currentChallengeId,
          otp: otp,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Email verified successfully! You can now log in.',
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Verification Failed'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleResend() async {
    if (_cooldownSeconds > 0) return;

    setState(() => _isLoading = true);

    try {
      final repo = ref.read(authRepositoryProvider);
      OtpChallengeResponse newChallenge;

      if (widget.purpose == OtpPurpose.register) {
        newChallenge = await repo.resendRegistrationOtp(
          challengeId: _currentChallengeId,
        );
      } else if (widget.purpose == OtpPurpose.login) {
        newChallenge = await repo.resendLoginOtp(
          challengeId: _currentChallengeId,
        );
      } else {
        newChallenge = await repo.resendEmailVerificationOtp(
          challengeId: _currentChallengeId,
        );
      }

      setState(() {
        _currentChallengeId = newChallenge.challengeId;
        _cooldownSeconds = 60;
        _expirySeconds = newChallenge.expiresInSeconds;
        _otpController.clear();
      });

      _startTimers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A new verification code was sent to your email!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to resend code: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    String title;
    String description;

    if (widget.purpose == OtpPurpose.login) {
      title = 'Login Verification';
      description =
          'Enter the 6-digit security code sent to:\n${widget.email}';
    } else if (widget.purpose == OtpPurpose.verifyEmail) {
      title = 'Verify Existing Account';
      description =
          'Enter the 6-digit code sent to:\n${widget.email} to activate your account.';
    } else {
      title = 'Verify Your Email';
      description =
          'Enter the 6-digit verification code sent to:\n${widget.email} to complete registration.';
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.purpose == OtpPurpose.login
                          ? Icons.security_outlined
                          : Icons.mark_email_read_outlined,
                      size: 64,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Expires in: ${_formatExpiryTime(_expirySeconds)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _expirySeconds <= 60
                        ? Colors.red
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                // Custom 6-digit OTP Box view
                GestureDetector(
                  onTap: () {
                    _focusNode.requestFocus();
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Hidden TextField
                      Opacity(
                        opacity: 0,
                        child: SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: TextField(
                            controller: _otpController,
                            focusNode: _focusNode,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (val) {
                              setState(() {});
                              if (val.length == 6) {
                                _handleVerify();
                              }
                            },
                          ),
                        ),
                      ),
                      // Display Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(6, (index) {
                          final codeText = _otpController.text;
                          String char = "";
                          if (index < codeText.length) {
                            char = codeText[index];
                          }

                          final isFocused =
                              _focusNode.hasFocus &&
                              (index == codeText.length ||
                                  (index == 5 && codeText.length == 6));

                          return Container(
                            width: 48,
                            height: 56,
                            decoration: BoxDecoration(
                              color: isFocused
                                  ? (isDark
                                        ? const Color(0xFF2A2E2A)
                                        : const Color(0xFFE8F5E9))
                                  : (isDark
                                        ? const Color(0xFF1E221E)
                                        : const Color(0xFFF1F5F1)),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isFocused
                                    ? theme.colorScheme.primary
                                    : (isDark
                                          ? Colors.grey.shade800
                                          : Colors.grey.shade300),
                                width: isFocused ? 2 : 1,
                              ),
                              boxShadow: isFocused
                                  ? [
                                      BoxShadow(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              char,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
                ElevatedButton(
                  onPressed: _isLoading ? null : _handleVerify,
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Verify & Continue'),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Didn't receive the code? ",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _cooldownSeconds == 0 ? _handleResend : null,
                      child: Text(
                        _cooldownSeconds > 0
                            ? 'Resend in ${_cooldownSeconds}s'
                            : 'Resend Code',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: _cooldownSeconds > 0
                              ? theme.colorScheme.onSurface.withValues(
                                  alpha: 0.4,
                                )
                              : theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
