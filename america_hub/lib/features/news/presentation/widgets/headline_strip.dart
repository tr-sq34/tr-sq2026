import 'package:flutter/material.dart';

import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_remote_image.dart';
import '../../../../core/widgets/section_unavailable.dart';
import '../../application/news_controller.dart';
import '../../domain/entities/news_article.dart';

/// Ana sayfadaki "Amerika'dan Manşetler" şeridi.
///
/// Kart görünümü eskisiyle aynı, içeriği değil: sabit üç haberin yerini Haber
/// Merkezi'nin okuduğu depo aldı. Manşet, panelden sıra numarası verilmiş
/// haberden başka bir şey değil; bu yüzden şerit ile Haber Merkezi'nin ayrı
/// düşmesi mümkün değil.
class HeadlineStrip extends StatefulWidget {
  const HeadlineStrip({
    super.key,
    required this.controller,
    required this.onOpenArticle,
    required this.onOpenNewsCenter,
  });

  final NewsController controller;
  final ValueChanged<NewsArticle> onOpenArticle;
  final VoidCallback onOpenNewsCenter;

  @override
  State<HeadlineStrip> createState() => _HeadlineStripState();
}

class _HeadlineStripState extends State<HeadlineStrip> {
  int _idx = 0;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final state = widget.controller.headlines;
      // İstek düştüğünde şerit sessizce kaybolmuyordu diye değil, kaybolduğu
      // için eklendi: "bugün manşet yok" ile "haber servisine ulaşılamadı"
      // ekranda aynı görünüyordu ve üye hangisi olduğunu bilemiyordu.
      if (state is AsyncFailure<List<NewsArticle>>) {
        return SectionUnavailable(
          title: 'Manşetler',
          message: state.message,
          onRetry: () => widget.controller.loadHeadlines(),
        );
      }
      // Manşet yoksa bölüm de yok: boş bir kutu ya da eski demo haberleri
      // göstermek, olmayan bir yayını varmış gibi sunmak olurdu.
      if (state is! AsyncData<List<NewsArticle>>) return const SizedBox.shrink();
      final headlines = state.value;
      if (headlines.isEmpty) return const SizedBox.shrink();
      final index = _idx.clamp(0, headlines.length - 1);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
        child: Column(
          children: [
            _Header(onOpenNewsCenter: widget.onOpenNewsCenter),
            const SizedBox(height: 12),
            Container(
              height: 230,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF1E293B)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: _Feature(
                      article: headlines[index],
                      onTap: () => widget.onOpenArticle(headlines[index]),
                    ),
                  ),
                  if (headlines.length > 1)
                    _Thumbnails(
                      headlines: headlines,
                      selected: index,
                      onSelect: (value) => setState(() => _idx = value),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.onOpenNewsCenter});

  final VoidCallback onOpenNewsCenter;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      const Row(
        children: [
          Icon(Icons.newspaper_rounded, size: 14, color: Color(0xFFF43F5E)),
          SizedBox(width: 8),
          Text(
            'AMERİKA\'DAN MANŞETLER',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF334155),
              letterSpacing: 1.1,
            ),
          ),
        ],
      ),
      // Eskiden burada dokunulamayan bir "Canlı Haberler" rozeti vardı; yerini
      // haberlerin tamamına götüren tek giriş aldı.
      InkWell(
        onTap: onOpenNewsCenter,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F3FF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFF6355D8).withValues(alpha: 0.1),
            ),
          ),
          child: const Row(
            children: [
              Text(
                'Haber Merkezi',
                style: TextStyle(
                  color: Color(0xFF6355D8),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_rounded,
                size: 10,
                color: Color(0xFF6355D8),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Feature extends StatelessWidget {
  const _Feature({required this.article, required this.onTap});

  final NewsArticle article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (article.imageUrl case final String url)
          AppRemoteImage(imageUrl: url, semanticLabel: article.title),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.2),
                Colors.black.withValues(alpha: 0.8),
              ],
              stops: const [0.5, 0.7, 1.0],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      article.category.label.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    article.timeLabel(),
                    style: const TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                article.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _Thumbnails extends StatelessWidget {
  const _Thumbnails({
    required this.headlines,
    required this.selected,
    required this.onSelect,
  });

  final List<NewsArticle> headlines;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
    height: 54,
    color: const Color(0xFF020617).withValues(alpha: 0.9),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Row(
      children: [
        for (var i = 0; i < headlines.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: selected == i
                        ? const Color(0xFF1E293B)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected == i
                          ? const Color(0xFF6355D8)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: AppRemoteImage(
                            imageUrl: headlines[i].imageUrl ?? '',
                            semanticLabel: headlines[i].title,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          headlines[i].title,
                          style: TextStyle(
                            color: selected == i
                                ? Colors.white
                                : const Color(0xFF94A3B8),
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
