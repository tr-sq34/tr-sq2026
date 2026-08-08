import 'package:flutter/foundation.dart';

import '../../../core/network/api_client.dart';

class MemberCapabilities {
  const MemberCapabilities({
    required this.identityVerified,
    required this.auctionSellerEligible,
  });

  const MemberCapabilities.none()
    : identityVerified = false,
      auctionSellerEligible = false;

  final bool identityVerified;
  final bool auctionSellerEligible;

  factory MemberCapabilities.fromJson(Map<String, dynamic> json) =>
      MemberCapabilities(
        identityVerified: json['identityVerified'] == true,
        auctionSellerEligible: json['auctionSellerEligible'] == true,
      );
}

/// Reads the Community projection written after a Stripe Identity webhook.
/// This intentionally does not call Stripe from the device.
class MemberCapabilitiesController extends ChangeNotifier {
  MemberCapabilitiesController(this._communityClient, this._verificationClient);

  final ApiClient _communityClient;
  final ApiClient _verificationClient;
  MemberCapabilities value = const MemberCapabilities.none();
  bool isLoading = false;
  String? errorMessage;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final response = await _communityClient.get<Map<String, dynamic>>(
        '/community/me/capabilities',
      );
      final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
      value = MemberCapabilities.fromJson(data);
    } catch (_) {
      // A temporary read failure must never grant seller privileges.
      value = const MemberCapabilities.none();
      errorMessage = 'Hesap durumu şu anda yüklenemedi.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Creates a short-lived Stripe Identity session through the Vault service.
  /// The device receives only the hosted verification URL, never Stripe keys
  /// or document data.
  Future<Uri> startVerification() async {
    final response = await _verificationClient.post<Map<String, dynamic>>(
      '/verification/sessions',
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    final rawUrl = data['url'] as String?;
    final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (url == null || url.scheme != 'https') {
      throw StateError('Doğrulama oturumu güvenli olarak başlatılamadı.');
    }
    return url;
  }
}
