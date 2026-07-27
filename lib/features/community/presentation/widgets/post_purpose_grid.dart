import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/community_post.dart';

class PostPurposeGrid extends StatelessWidget {
  const PostPurposeGrid({super.key, required this.selected, required this.onSelected});
  final CommunityPostPurpose selected;
  final ValueChanged<CommunityPostPurpose> onSelected;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
        child: Row(children: [
          _item(CommunityPostPurpose.standard, 'Standart', Icons.campaign_outlined, const Color(0xFFE8F7EF)),
          const SizedBox(width: 8),
          _item(CommunityPostPurpose.imeceHelp, 'Destek', Icons.volunteer_activism_outlined, const Color(0xFFFFF1D8)),
          const SizedBox(width: 8),
          _item(CommunityPostPurpose.travelerMatch, 'Bavulda Yer', Icons.luggage_outlined, const Color(0xFFE5F3FF)),
          const SizedBox(width: 8),
          _item(CommunityPostPurpose.anonymousAdvice, 'Anonim', Icons.visibility_off_outlined, const Color(0xFFF0E9FF)),
        ]),
      );

  Widget _item(CommunityPostPurpose value, String label, IconData icon, Color fill) {
    final isSelected = selected == value;
    return Expanded(child: Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 3),
          decoration: BoxDecoration(
            color: isSelected ? fill : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isSelected ? AppColors.primary : const Color(0xFFE9E7EE), width: isSelected ? 1.5 : 1),
            boxShadow: isSelected ? const [BoxShadow(color: Color(0x140E0B18), blurRadius: 10, offset: Offset(0, 4))] : null,
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 34, height: 34, decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(11)), child: Icon(icon, size: 19, color: AppColors.primary)),
            const SizedBox(height: 5),
            Text(label, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, height: 1.05, fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600)),
          ]),
        ),
      ),
    ));
  }
}
