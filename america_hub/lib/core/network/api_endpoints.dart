abstract final class ApiEndpoints {
  // ApiConfig.baseUrl already contains `/v1`; keep endpoint paths relative so
  // requests resolve to https://api.turksquare.com/v1/auth/… exactly once.
  static const authLogin = 'auth/login';
  static const authEmailStatus = 'auth/email/status';
  static const authEmailVerificationConfirm = 'auth/email/verification/confirm';
  static const authEmailVerificationResend = 'auth/email/verification/resend';
  static const authRegister = 'auth/register';
  static const authRefresh = 'auth/refresh';
  static const authLogout = 'auth/logout';
  static const authOnboarding = 'auth/onboarding';
  static const authPasskeyRegistrationOptions =
      'auth/passkeys/registration/options';
  static const authPasskeyRegistrationVerify =
      'auth/passkeys/registration/verify';
  static const authPasskeyAuthenticationOptions =
      'auth/passkeys/authentication/options';
  static const authPasskeyAuthenticationVerify =
      'auth/passkeys/authentication/verify';
  static const communityFeed = '/community/feed';
  static const communityHomeSummary = '/community/home/summary';
  static const communityPosts = '/community/posts';
  static const communityStories = '/community/stories';
  static const communityStoryAudienceContacts =
      '/community/me/story-audience-contacts';
  static const communityMyStoryHighlights = '/community/me/story-highlights';
  static const mediaUploadPresign = '/media/uploads/presign';
  static const eventsUpcoming = '/events';
  static const marketplaceListings = '/marketplace/listings';
  static const profile = '/profile/me';
}
