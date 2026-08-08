abstract final class ApiEndpoints {
  static const authLogin = '/auth/login';
  static const authRegister = '/auth/register';
  static const authRefresh = '/auth/refresh';
  static const authLogout = '/auth/logout';
  static const authPasskeyRegistrationOptions =
      '/auth/passkeys/registration/options';
  static const authPasskeyRegistrationVerify =
      '/auth/passkeys/registration/verify';
  static const authPasskeyAuthenticationOptions =
      '/auth/passkeys/authentication/options';
  static const authPasskeyAuthenticationVerify =
      '/auth/passkeys/authentication/verify';
  static const communityFeed = '/community/feed';
  static const communityPosts = '/community/posts';
  static const communityStories = '/community/stories';
  static const mediaUploadPresign = '/media/uploads/presign';
  static const eventsUpcoming = '/events';
  static const marketplaceListings = '/marketplace/listings';
  static const profile = '/profile/me';
}
