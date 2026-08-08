import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/network/api_exception.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.onComplete});

  final Future<void> Function(
    String city,
    String regionCode,
    List<String> interests,
    String primaryIntent,
  )
  onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _location = TextEditingController();
  final Set<String> _interests = {'Topluluk', 'Çarşı', 'Yemek'};
  String? _regionCode;
  bool _loading = false;
  bool _locating = false;
  String? _error;
  bool _showSuggestions = false;

  final List<String> _mockLocationSuggestions = [
    'Queens, NY, USA',
    'Queens Village, NY, USA',
    'Queensbury, NY, USA',
    'Manhattan, NY, USA',
    'Brooklyn, NY, USA',
    'Jersey City, NJ, USA',
    'Paterson, NJ, USA',
  ];

  static const _interestChoices = <_InterestChoice>[
    _InterestChoice('Topluluk', Icons.groups_rounded),
    _InterestChoice('Çarşı', Icons.storefront_rounded),
    _InterestChoice('Kariyer', Icons.work_rounded),
    _InterestChoice('Yemek', Icons.restaurant_rounded),
    _InterestChoice('Kültür', Icons.museum_rounded),
    _InterestChoice('Spor', Icons.sports_soccer_rounded),
    _InterestChoice('Etkinlik', Icons.celebration_rounded),
    _InterestChoice('Aile', Icons.family_restroom_rounded),
    _InterestChoice('Eğitim', Icons.school_rounded),
    _InterestChoice('Seyahat', Icons.flight_takeoff_rounded),
  ];

  @override
  void dispose() {
    _location.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const _LocationException(
          'Konum izni verilmedi. Konumunu arayarak seçebilirsin.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 12),
        ),
      );
      
      if (!mounted) return;
      
      // For this refactor, we simulate the text update as in the design
      // In a real app, this would be a reverse geocoding call
      setState(() {
        _location.text = 'Manhattan, New York';
        _showSuggestions = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Mevcut konumunuz başarıyla alındı: Manhattan'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF6C5CE7),
        ),
      );
      
      debugPrint(
        'Approximate location acquired: ${position.accuracy.round()}m',
      );
    } on _LocationException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on TimeoutException {
      if (mounted) {
        setState(
          () => _error = 'Konum alınamadı. Şehir veya bölgeyi yazabilirsin.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Konum alınamadı. Şehir veya bölgeyi yazabilirsin.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _submit() async {
    HapticFeedback.mediumImpact();
    final city = _location.text.trim();
    if (city.length < 2) {
      setState(() => _error = 'Lütfen bulunduğun şehir veya bölgeyi yazın.');
      return;
    }
    final regionCode = _regionCode ?? _inferRegionCode(city);
    if (regionCode == null) {
      setState(() => _error = 'Listeden bir konum seçin veya bölgeyi belirtin (örn: NY).');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.onComplete(
        city,
        regionCode,
        _interests.toList(growable: false),
        'community',
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Bilgiler kaydedilemedi. Lütfen tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _inferRegionCode(String value) {
    final normalized = value.toLowerCase();
    const locations = <String, String>{
      'new jersey': 'NJ',
      'jersey city': 'NJ',
      'newark': 'NJ',
      'paterson': 'NJ',
      'new york': 'NY',
      'queens': 'NY',
      'brooklyn': 'NY',
      'manhattan': 'NY',
      'california': 'CA',
      'los angeles': 'CA',
      'florida': 'FL',
      'miami': 'FL',
      'texas': 'TX',
      'austin': 'TX',
      'illinois': 'IL',
      'chicago': 'IL',
      'massachusetts': 'MA',
      'boston': 'MA',
      'pennsylvania': 'PA',
      'philadelphia': 'PA',
      'virginia': 'VA',
      'maryland': 'MD',
    };
    for (final entry in locations.entries) {
      if (normalized.contains(entry.key)) return entry.value;
    }
    final match = RegExp(r'[,\s]([A-Za-z]{2})$').firstMatch(value);
    return match?.group(1)?.toUpperCase();
  }

  void _toggleInterest(String label) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_interests.contains(label)) {
        if (_interests.length > 1) _interests.remove(label);
      } else {
        _interests.add(label);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = AppColors.primary;
    const secondaryGradient = LinearGradient(
      colors: [AppColors.primary, Color(0xFF8C7AE6)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FD),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text(
              'Atla',
              style: TextStyle(
                color: Color(0xFF888AAA),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              primaryColor.withOpacity(0.15),
                              primaryColor.withOpacity(0.05),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          border: Border.all(
                            color: primaryColor.withOpacity(0.2),
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.location_on_rounded,
                            size: 38,
                            color: primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'Sana yakın bir TurkSquare oluşturalım',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1E1E2D),
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        'Tercihlerini istediğin zaman profilinden güncelleyebilirsin.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF7A7E9A),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    _buildLocationCard(primaryColor),

                    const SizedBox(height: 20),

                    _buildInterestsCard(primaryColor),

                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      _buildErrorBanner(_error!),
                    ],

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            _buildBottomActionBar(primaryColor, secondaryGradient),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1E2D).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFEFEFF4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.my_location_rounded,
                  size: 20,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Bulunduğun yer',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E1E2D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Akış ve Çarşı\'da önce yerel içerikleri görürsün. Diğer eyaletler de her zaman görünür.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF7A7E9A),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),

          OutlinedButton(
            onPressed: _locating || _loading ? null : _useCurrentLocation,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: BorderSide(color: primaryColor.withOpacity(0.4), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              backgroundColor: primaryColor.withOpacity(0.03),
              disabledBackgroundColor: Colors.transparent,
            ),
            child: _locating
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: primaryColor,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.explore_outlined, color: primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Mevcut konumumu kullan',
                        style: TextStyle(
                          color: primaryColor,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),

          TextField(
            controller: _location,
            enabled: !_loading,
            onChanged: (val) {
              setState(() {
                _showSuggestions = val.isNotEmpty;
                _regionCode = null;
              });
            },
            decoration: InputDecoration(
              labelText: 'Şehir veya bölge',
              labelStyle: const TextStyle(
                color: Color(0xFF7A7E9A),
                fontSize: 13,
              ),
              prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF7A7E9A)),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_location.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF999BB3)),
                      onPressed: () {
                        _location.clear();
                        setState(() {
                          _showSuggestions = false;
                          _regionCode = null;
                        });
                      },
                    ),
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EDFF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              filled: true,
              fillColor: const Color(0xFFF6F7FB),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: primaryColor, width: 1.5),
              ),
            ),
          ),

          if (_showSuggestions) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFEFEFF4)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: _mockLocationSuggestions
                    .where((item) => item.toLowerCase().contains(_location.text.toLowerCase()))
                    .map(
                      (suggestion) => ListTile(
                        dense: true,
                        leading: Icon(Icons.place_outlined, size: 18, color: primaryColor),
                        title: Text(
                          suggestion,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        onTap: () {
                          setState(() {
                            _location.text = suggestion;
                            _showSuggestions = false;
                            _regionCode = _inferRegionCode(suggestion);
                          });
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
          ],

          const SizedBox(height: 8),
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 13, color: Color(0xFF999BB3)),
              SizedBox(width: 6),
              Text(
                'Yazdıkça Google Maps sonuçları burada görünecek.',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF999BB3),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInterestsCard(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E1E2D).withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFEFEFF4),
          width: 1,
        ),
      ),
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.interests_rounded,
                  size: 20,
                  color: primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'İlgi alanların',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E1E2D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Sana uygun içerikleri ve toplulukları öne çıkaralım.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF7A7E9A),
            ),
          ),
          const SizedBox(height: 18),

          Wrap(
            spacing: 8.0,
            runSpacing: 10.0,
            children: _interestChoices.map((choice) {
              final isSelected = _interests.contains(choice.label);
              return GestureDetector(
                onTap: _loading ? null : () => _toggleInterest(choice.label),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(
                            colors: [Color(0xFF6C5CE7), Color(0xFF8272F0)],
                          )
                        : null,
                    color: isSelected ? null : const Color(0xFFF3F4F9),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        choice.icon,
                        size: 17,
                        color: isSelected ? Colors.white : const Color(0xFF5A5C75),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        choice.label,
                        style: TextStyle(
                          color: isSelected ? Colors.white : const Color(0xFF383A4D),
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Colors.white,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(Color primaryColor, Gradient gradient) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loading ? null : _submit,
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_loading)
                   const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                else ...[
                  Text(
                    _interests.isEmpty
                        ? 'Devam et'
                        : 'Devam et (${_interests.length} Seçildi)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(String message) => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFEEF0),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFFC53A4A)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Color(0xFFA92D3B), height: 1.3),
          ),
        ),
      ],
    ),
  );
}

class _InterestChoice {
  const _InterestChoice(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _LocationException implements Exception {
  const _LocationException(this.message);
  final String message;
}
