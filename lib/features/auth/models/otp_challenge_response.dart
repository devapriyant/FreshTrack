enum OtpPurpose { register, login, verifyEmail }

class OtpChallengeResponse {
  final String challengeId;
  final String maskedEmail;
  final int expiresInSeconds;
  final String message;
  final bool verificationRequired;

  const OtpChallengeResponse({
    required this.challengeId,
    required this.maskedEmail,
    required this.expiresInSeconds,
    required this.message,
    this.verificationRequired = false,
  });

  factory OtpChallengeResponse.fromJson(Map<String, dynamic> json) {
    return OtpChallengeResponse(
      challengeId: json['challenge_id']?.toString() ?? '',
      maskedEmail: json['email']?.toString() ?? '',
      expiresInSeconds: json['expires_in_seconds'] is int
          ? json['expires_in_seconds'] as int
          : int.tryParse(json['expires_in_seconds']?.toString() ?? '600') ?? 600,
      message: json['message']?.toString() ?? 'Verification code sent.',
      verificationRequired: json['verification_required'] == true,
    );
  }
}
