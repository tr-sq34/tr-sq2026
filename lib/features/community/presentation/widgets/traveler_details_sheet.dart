import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/community_post.dart';

class TravelerDetailsSheet extends StatefulWidget {
  const TravelerDetailsSheet({super.key, this.initialValue});
  final TravelerMatchDetails? initialValue;

  @override
  State<TravelerDetailsSheet> createState() => _TravelerDetailsSheetState();
}

class _TravelerDetailsSheetState extends State<TravelerDetailsSheet> {
  late final TextEditingController _from;
  late final TextEditingController _to;
  late final TextEditingController _package;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  @override
  void initState() {
    super.initState();
    _from = TextEditingController(text: widget.initialValue?.from);
    _to = TextEditingController(text: widget.initialValue?.to);
    _package = TextEditingController(text: widget.initialValue?.packageDetails);
    final travelAt = widget.initialValue?.travelAt;
    if (travelAt != null) { _date = travelAt; _time = TimeOfDay.fromDateTime(travelAt); }
  }

  @override
  void dispose() { _from.dispose(); _to.dispose(); _package.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final result = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 730)));
    if (!mounted || result == null) return;
    setState(() => _date = result);
  }

  Future<void> _pickTime() async {
    final result = await showTimePicker(context: context, initialTime: _time);
    if (!mounted || result == null) return;
    setState(() => _time = result);
  }

  void _submit() {
    if (_from.text.trim().isEmpty || _to.text.trim().isEmpty || _package.text.trim().isEmpty) return;
    final travelAt = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    Navigator.of(context).pop(TravelerMatchDetails(from: _from.text.trim(), to: _to.text.trim(), travelAt: travelAt, packageDetails: _package.text.trim()));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD8D5DF), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              const Text('Bavulda Yer Var', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Yolculuğunu ve taşıyabileceğin küçük paketi paylaş.', style: TextStyle(color: AppColors.textMuted)),
              const SizedBox(height: 20),
              _field(controller: _from, label: 'Kalkış şehri', icon: Icons.flight_takeoff_outlined, hint: 'Örn. New York, NY'),
              const SizedBox(height: 12),
              _field(controller: _to, label: 'Varış şehri', icon: Icons.flight_land_outlined, hint: 'Örn. İstanbul, TR'),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: _pickerTile(icon: Icons.calendar_month_outlined, label: 'Tarih', value: '${_date.day}.${_date.month}.${_date.year}', onTap: _pickDate)), const SizedBox(width: 12), Expanded(child: _pickerTile(icon: Icons.schedule_outlined, label: 'Saat', value: _time.format(context), onTap: _pickTime))]),
              const SizedBox(height: 12),
              _field(controller: _package, label: 'Paket / eşya detayı', icon: Icons.inventory_2_outlined, hint: 'Örn. Evrak veya 2 kg küçük paket', maxLines: 2),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _submit, icon: const Icon(Icons.check_rounded), label: const Text('Yolculuk bilgisini ekle'))),
            ]),
          )),
        ),
      );

  Widget _field({required TextEditingController controller, required String label, required IconData icon, required String hint, int maxLines = 1}) => TextField(
        controller: controller, maxLines: maxLines,
        decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, color: AppColors.primary), filled: true, fillColor: const Color(0xFFF8F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
      );

  Widget _pickerTile({required IconData icon, required String label, required String value, required VoidCallback onTap}) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(16),
        child: Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF8F7FA), borderRadius: BorderRadius.circular(16)), child: Row(children: [Icon(icon, color: AppColors.primary), const SizedBox(width: 8), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]))])),
      );
}

class LocationPickerSheet extends StatefulWidget {
  const LocationPickerSheet({super.key, this.initialValue});
  final String? initialValue;

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  late final TextEditingController _controller;

  @override
  void initState() { super.initState(); _controller = TextEditingController(text: widget.initialValue); }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _submit([String? value]) {
    final location = (value ?? _controller.text).trim();
    if (location.isNotEmpty) Navigator.of(context).pop(location);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Material(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: SafeArea(top: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD8D5DF), borderRadius: BorderRadius.circular(99)))),
              const SizedBox(height: 18),
              const Align(alignment: Alignment.centerLeft, child: Text('Konum ekle', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              const SizedBox(height: 14),
              TextField(controller: _controller, autofocus: true, textInputAction: TextInputAction.done, onSubmitted: _submit, decoration: InputDecoration(hintText: 'Mekân veya adres ara', prefixIcon: const Icon(Icons.search_rounded), filled: true, fillColor: const Color(0xFFF8F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
              const SizedBox(height: 12),
              ListTile(leading: const Icon(Icons.my_location_outlined, color: AppColors.primary), title: const Text('Mevcut konum'), subtitle: const Text('Canlı konum izni geldiğinde otomatik dolacak'), onTap: () => _submit('Mevcut konum')),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _submit, child: const Text('Konumu ekle'))),
            ]),
          )),
        ),
      );
}
