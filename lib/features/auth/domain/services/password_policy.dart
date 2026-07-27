/// Client-side usability validation. The server remains the authoritative
/// verifier and must additionally enforce breached-password screening.
abstract final class PasswordPolicy {
  static const minLength = 12;

  static String? validate(String value, {String? email, String? name}) {
    final password = value.trim();
    if (password.length < minLength)
      return 'Şifreniz en az $minLength karakter olmalıdır.';
    if (password.length > 128)
      return 'Şifreniz en fazla 128 karakter olabilir.';
    final lowered = password.toLowerCase();
    final localEmail = email?.split('@').first.toLowerCase();
    if (localEmail != null &&
        localEmail.length >= 3 &&
        lowered.contains(localEmail))
      return 'Şifreniz e-posta adresinizi içermemelidir.';
    final normalizedName = name?.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (normalizedName != null &&
        normalizedName.length >= 3 &&
        lowered.contains(normalizedName))
      return 'Şifreniz adınızı içermemelidir.';
    return null;
  }
}
