import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../../core/widgets/app_state_views.dart';
import '../../../community/application/community_comments_controller.dart';
import '../../../community/domain/repositories/content_moderation_repository.dart';
import '../../application/news_controller.dart';
import '../../domain/entities/news_article.dart';
import '../widgets/news_card.dart';
import 'news_article_screen.dart';

/// Sağ çeker menüdeki Haber Merkezi.
///
/// Ana sayfadaki "Amerika'dan Manşetler" şeridiyle aynı depoyu okur; buradaki
/// liste manşet filtresi olmayan hâlidir. Habere dokununca [NewsArticleScreen]
/// açılır, yorumlar akışın editörüyle yazılır.
class NewsCenterScreen extends StatefulWidget {
  const NewsCenterScreen({
    super.key,
    required this.controller,
    required this.commentsController,
    required this.moderationRepository,
    required this.viewerId,
  });

  final NewsController controller;

  /// Haber yorumları için kurulmuş denetleyici — akıştakiyle aynı sınıf, farklı
  /// depo. Bileşenin aynısı olması istendiği için ayrı bir tür yazılmadı.
  final CommunityCommentsController commentsController;
  final ContentModerationRepository moderationRepository;

  /// Detay ekranına aktarılır; yorum silme izni orada kullanılıyor.
  final String viewerId;

  @override
  State<NewsCenterScreen> createState() => _NewsCenterScreenState();
}

class _NewsCenterScreenState extends State<NewsCenterScreen> {
  @override
  void initState() {
    super.initState();
    // Denetleyici ana sayfadaki manşet şeridiyle ortak: şerit hâlâ ekranda
    // dinlerken buradan yükleme başlatmak, çizim sürerken ona "yeniden çiz"
    // demek oluyordu ve Flutter bunu hata olarak atıyordu. Çerçeve bitsin,
    // sonra iste.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.load(category: widget.controller.category);
    });
  }

  void _openArticle(NewsArticle article) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NewsArticleScreen(
        articleId: article.id,
        controller: widget.controller,
        commentsController: widget.commentsController,
        moderationRepository: widget.moderationRepository,
        viewerId: widget.viewerId,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Haber Merkezi',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => Column(
        children: [
          _CategoryBar(
            selected: widget.controller.category,
            onSelected: (category) =>
                widget.controller.load(category: category),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    ),
  );

  Widget _buildList() => switch (widget.controller.articles) {
    AsyncLoading<List<NewsArticle>>() => const AppLoadingView(
      label: 'Haberler yükleniyor…',
    ),
    AsyncFailure<List<NewsArticle>>(:final message) => AppErrorState(
      message: message,
      onRetry: () => widget.controller.load(category: widget.controller.category),
    ),
    AsyncData<List<NewsArticle>>(value: final articles) when articles.isEmpty =>
      const AppEmptyState(
        icon: Icons.newspaper_rounded,
        title: 'Bu kategoride haber yok',
        message:
            'Yeni haberler eklendikçe burada görünecek. Başka bir kategoriye '
            'göz atabilirsin.',
      ),
    AsyncData<List<NewsArticle>>(value: final articles) => RefreshIndicator(
      onRefresh: () => widget.controller.load(category: widget.controller.category),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: articles.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) => NewsCard(
          article: articles[index],
          onTap: () => _openArticle(articles[index]),
        ),
      ),
    ),
  };
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.selected, required this.onSelected});

  final NewsCategory? selected;
  final ValueChanged<NewsCategory?> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        _chip(label: 'Tümü', value: null),
        for (final category in NewsCategory.values)
          _chip(label: category.label, value: category),
      ],
    ),
  );

  Widget _chip({required String label, required NewsCategory? value}) {
    final isSelected = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => onSelected(value),
        showCheckmark: false,
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primary.withValues(alpha: .12),
        side: BorderSide(
          color: isSelected ? AppColors.primary : AppColors.surfaceBorder,
        ),
        labelStyle: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: isSelected ? AppColors.primary : AppColors.textSecondary,
        ),
      ),
    );
  }
}
