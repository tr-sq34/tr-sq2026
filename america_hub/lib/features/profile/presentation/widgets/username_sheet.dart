import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/profile_controller.dart';
import '../../domain/entities/user_profile.dart';

/// Kullanıcı adı seçme ekranı.
///
/// Üye yazarken cevap veriyor, çünkü kaydete bastıktan sonra "alınmış" demek,
/// beğendiği adı boşuna beğendirmek olurdu. Ama son sözü kaydetme anı söylüyor:
/// aradaki saniyelerde aynı adı başkası alabilir ve bu ekran o durumu da
/// gösterebiliyor.
class UsernameSheet extends StatefulWidget {
  const UsernameSheet({super.key, required this.controller, required this.profile});

  final ProfileController controller;
  final UserProfile profile;

  @override
  State<UsernameSheet> createState() => _UsernameSheetState();
}

class _UsernameSheetState extends State<UsernameSheet> {
  late final TextEditingController _field =
      TextEditingController(text: widget.profile.username ?? '');
  Timer? _debounce;

  /// Denetim sonucu. Null ise henüz sorulmadı; ekran o zaman ne yeşil ne kırmızı
  /// gösteriyor, çünkü bilmediği bir şeyi söylemiş olurdu.
  UsernameCheck? _check;
  bool _checking = false;
  String? _saveError;
  bool _saving = false;

  bool get _unchanged =>
      _field.text.trim().toLowerCase() == (widget.profile.username ?? '');

  @override
  void dispose() {
    _debounce?.cancel();
    _field.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    setState(() {
      _check = null;
      _saveError = null;
    });
    final wanted = value.trim().toLowerCase();
    if (wanted.isEmpty || wanted == widget.profile.username) return;
    // Her tuşta bir istek göndermek, üye "ahmet" yazarken beş sorgu demek.
    _debounce = Timer(const Duration(milliseconds: 450), () => _runCheck(wanted));
  }

  Future<void> _runCheck(String wanted) async {
    setState(() => _checking = true);
    final result = await widget.controller.checkUsername(wanted);
    if (!mounted || _field.text.trim().toLowerCase() != wanted) return;
    setState(() {
      _check = result;
      _checking = false;
    });
  }

  Future<void> _save() async {
    final wanted = _field.text.trim().toLowerCase();
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final error = await widget.controller.saveUsername(wanted.isEmpty ? null : wanted);
    if (!mounted) return;
    setState(() => _saving = false);
    if (error != null) {
      setState(() => _saveError = error);
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    final canSave = !_saving &&
        !_checking &&
        !_unchanged &&
        (_field.text.trim().isEmpty || (check?.available ?? false));
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Kullanıcı adın',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Seni bu adla arayabilir, anabilir ve profiline bu adla ulaşabilirler. '
            'Bir kişide yalnızca bir tane olabilir.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _field,
            autofocus: true,
            maxLength: 24,
            textInputAction: TextInputAction.done,
            onChanged: _onChanged,
            onSubmitted: (_) => canSave ? _save() : null,
            inputFormatters: [
              // Büyük harf ve boşluk hiç girilemiyor: kural sunucuda zaten var,
              // burada da olması üyeyi yazarken reddedilen bir ada uğratmıyor.
              FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_.]')),
              TextInputFormatter.withFunction(
                (previous, next) => next.copyWith(text: next.text.toLowerCase()),
              ),
            ],
            decoration: InputDecoration(
              prefixText: '@',
              hintText: 'kullaniciadi',
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: _checking
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : check == null
                      ? null
                      : Icon(
                          check.available
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: check.available
                              ? const Color(0xFF059669)
                              : AppColors.accentRose,
                        ),
            ),
          ),
          if (check != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                check.message,
                style: TextStyle(
                  fontSize: 12.5,
                  color: check.available
                      ? const Color(0xFF059669)
                      : AppColors.accentRose,
                ),
              ),
            ),
          if (_saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _saveError!,
                style: const TextStyle(fontSize: 12.5, color: AppColors.accentRose),
              ),
            ),
          if (widget.profile.username != null && _field.text.trim().isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Boş bıraktığında kullanıcı adın kaldırılır ve başkası alabilir.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: canSave ? _save : null,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Kaydet'),
          ),
        ],
      ),
    );
  }
}
