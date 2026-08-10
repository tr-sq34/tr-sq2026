import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/state/async_state.dart';
import '../../../profile/presentation/widgets/profile_badge_chip.dart';
import '../../application/journey_controller.dart';
import '../../domain/entities/journey.dart';

/// Gurbet Yolculuğu: the task hub, the badge cabinet and the leaderboard.
///
/// Three tabs rather than one long scroll, because they answer three different
/// questions: what do I do next, what have I collected, and where do I stand.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.controller});

  final JourneyController controller;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('Gurbet Yolculuğu'),
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      bottom: TabBar(
        controller: _tabs,
        labelColor: AppColors.profileAccent,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.profileAccent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        tabs: const [
          Tab(text: 'Görevler'),
          Tab(text: 'Rozetler'),
          Tab(text: 'Liderlik'),
        ],
      ),
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => TabBarView(
        controller: _tabs,
        children: [
          _TasksTab(state: widget.controller.journey, onRetry: widget.controller.load),
          _BadgesTab(state: widget.controller.badges, onRetry: widget.controller.load),
          _LeaderboardTab(
            state: widget.controller.leaderboard,
            scope: widget.controller.scope,
            onScopeChanged: widget.controller.loadLeaderboard,
          ),
        ],
      ),
    ),
  );
}

class _TasksTab extends StatelessWidget {
  const _TasksTab({required this.state, required this.onRetry});

  final AsyncState<JourneySnapshot> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => switch (state) {
    AsyncFailure<JourneySnapshot>(:final message) => _Retry(message: message, onRetry: onRetry),
    AsyncData<JourneySnapshot>(:final value) => ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _LevelCard(snapshot: value),
        if (value.perksFrozenUntil != null) ...[
          const SizedBox(height: 12),
          _FrozenNotice(until: value.perksFrozenUntil!),
        ],
        const SizedBox(height: 16),
        for (final stage in value.stages) _StageCard(stage: stage),
        if (value.stages.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text(
              'Görev haritası hazırlanıyor.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
      ],
    ),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.snapshot});

  final JourneySnapshot snapshot;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [AppColors.profileTint, AppColors.surface],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: AppColors.profileBorder),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LevelRing(level: snapshot.level, progress: snapshot.progress),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.levelTitle,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${snapshot.points} Gurbet XP · ${snapshot.badgeCount} rozet',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                  if (snapshot.nextLevelPoints != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Sv.${snapshot.nextLevel} ${snapshot.nextLevelTitle ?? ''} için '
                      '${(snapshot.nextLevelPoints! - snapshot.points).clamp(0, 1 << 30)} XP',
                      style: const TextStyle(fontSize: 12, color: AppColors.profileAccent),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const Icon(Icons.local_fire_department_rounded, size: 18, color: Color(0xFFE8712F)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                snapshot.streakDays > 0
                    ? '${snapshot.streakDays} günlük zincir · en iyi ${snapshot.streakBest}'
                    : 'Zincirin kırık. Bugün bir şey paylaş, yeniden başlasın.',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _LevelRing extends StatelessWidget {
  const _LevelRing({required this.level, required this.progress});

  final int level;
  final double progress;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    width: 64,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          height: 64,
          width: 64,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 6,
            backgroundColor: AppColors.surfaceBorder,
            valueColor: const AlwaysStoppedAnimation(AppColors.profileAccent),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Sv', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            Text(
              '$level',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ],
    ),
  );
}

class _FrozenNotice extends StatelessWidget {
  const _FrozenNotice({required this.until});

  final DateTime until;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4E5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFF3C88A)),
    ),
    child: Row(
      children: [
        const Icon(Icons.ac_unit_rounded, size: 18, color: Color(0xFFB4700F)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Ayrıcalıkların ${until.day}.${until.month}.${until.year} tarihine kadar '
            'dondurulmuş. Rozetlerin duruyor.',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A5A0B)),
          ),
        ),
      ],
    ),
  );
}

class _StageCard extends StatelessWidget {
  const _StageCard({required this.stage});

  final JourneyStage stage;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: stage.completed ? const Color(0xFF86E2B3) : AppColors.profileBorder,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${stage.ordinal}. ${stage.title}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${stage.doneCount}/${stage.tasks.length}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          stage.levelTitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final task in stage.tasks) _TaskRow(task: task),
        if (stage.reward.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.card_giftcard_rounded, size: 15, color: AppColors.profileAccent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage.reward,
                  style: const TextStyle(fontSize: 12, color: AppColors.profileAccent),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final JourneyTask task;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          task.completed ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 18,
          color: task.completed ? const Color(0xFF059669) : AppColors.textMuted,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: task.completed ? AppColors.textSecondary : AppColors.textPrimary,
                        decoration: task.completed ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  Text(
                    '+${task.points}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.profileAccent,
                    ),
                  ),
                ],
              ),
              Text(
                task.description,
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              if (!task.completed && task.target > 1) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: task.progress,
                          minHeight: 5,
                          backgroundColor: AppColors.canvas,
                          valueColor: const AlwaysStoppedAnimation(AppColors.profileAccent),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${task.current}/${task.target}',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _BadgesTab extends StatelessWidget {
  const _BadgesTab({required this.state, required this.onRetry});

  final AsyncState<List<JourneyBadge>> state;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => switch (state) {
    AsyncFailure<List<JourneyBadge>>(:final message) => _Retry(message: message, onRetry: onRetry),
    AsyncData<List<JourneyBadge>>(:final value) => _BadgeList(badges: value),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

class _BadgeList extends StatelessWidget {
  const _BadgeList({required this.badges});

  final List<JourneyBadge> badges;

  @override
  Widget build(BuildContext context) {
    final earned = badges.where((badge) => badge.earned).toList();
    final inProgress = badges.where((badge) => !badge.earned && badge.hasProgress).toList();
    final locked = badges
        .where((badge) => !badge.earned && !badge.hasProgress)
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        if (earned.isNotEmpty) _BadgeGroup(title: 'Kazanılanlar', badges: earned),
        if (inProgress.isNotEmpty) _BadgeGroup(title: 'Devam edenler', badges: inProgress),
        if (locked.isNotEmpty) _BadgeGroup(title: 'Kilitli', badges: locked),
        if (badges.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: Text(
              'Rozet katalogu yüklenemedi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }
}

class _BadgeGroup extends StatelessWidget {
  const _BadgeGroup({required this.title, required this.badges});

  final String title;
  final List<JourneyBadge> badges;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 6),
        child: Text(
          '$title · ${badges.length}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      for (final badge in badges) _BadgeRow(badge: badge),
      const SizedBox(height: 10),
    ],
  );
}

class _BadgeRow extends StatelessWidget {
  const _BadgeRow({required this.badge});

  final JourneyBadge badge;

  @override
  Widget build(BuildContext context) {
    final style = badgeTierStyle(badge.tier);
    final dimmed = !badge.earned;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dimmed ? AppColors.surfaceBorder : style.border,
          width: dimmed ? 1 : style.weight,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dimmed ? AppColors.canvas : style.fill,
            ),
            child: Icon(
              badge.isSecret && !badge.earned ? Icons.lock_outline : style.icon,
              size: 20,
              color: dimmed ? AppColors.textMuted : style.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        badge.title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: dimmed ? AppColors.textSecondary : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${badgeTierLabel(badge.tier)} · +${badge.points}',
                      style: TextStyle(fontSize: 11, color: dimmed ? AppColors.textMuted : style.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  badge.description,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (badge.hasProgress) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: badge.progress,
                            minHeight: 5,
                            backgroundColor: AppColors.canvas,
                            valueColor: AlwaysStoppedAnimation(style.ink),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${badge.current}/${badge.target}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ],
                if (badge.rarityPercent > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    // The reason to race: how few people have this.
                    'Üyelerin %${_rarity(badge.rarityPercent)}\'i aldı',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _rarity(double percent) =>
      percent >= 10 ? percent.toStringAsFixed(0) : percent.toStringAsFixed(1);
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({
    required this.state,
    required this.scope,
    required this.onScopeChanged,
  });

  final AsyncState<List<LeaderboardEntry>> state;
  final LeaderboardScope scope;
  final Future<void> Function(LeaderboardScope) onScopeChanged;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SegmentedButton<LeaderboardScope>(
          segments: const [
            ButtonSegment(value: LeaderboardScope.city, label: Text('Şehrim')),
            ButtonSegment(value: LeaderboardScope.region, label: Text('Eyaletim')),
            ButtonSegment(value: LeaderboardScope.global, label: Text('Genel')),
          ],
          selected: {scope},
          onSelectionChanged: (value) => onScopeChanged(value.first),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Son 7 günde kazanılan XP',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      ),
      Expanded(
        child: switch (state) {
          AsyncFailure<List<LeaderboardEntry>>(:final message) => Center(child: Text(message)),
          AsyncData<List<LeaderboardEntry>>(:final value) when value.isEmpty => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Bu hafta bu bölgede kimse puan toplamadı. İlk sen ol.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ),
          AsyncData<List<LeaderboardEntry>>(:final value) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: value.length,
            itemBuilder: (context, index) => _LeaderboardRow(entry: value[index]),
          ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    ],
  );
}

class _LeaderboardRow extends StatelessWidget {
  const _LeaderboardRow({required this.entry});

  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: entry.isSelf ? AppColors.profileTint : AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: entry.isSelf ? AppColors.profileAccent : AppColors.profileBorder,
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            '${entry.rank}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: entry.rank <= 3 ? AppColors.profileAccent : AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              Text(
                'Sv.${entry.level}'
                '${entry.city != null ? ' · ${entry.city}' : ''}'
                '${entry.regionCode != null ? ', ${entry.regionCode}' : ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          '${entry.score} XP',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ],
    ),
  );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(message, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
      ],
    ),
  );
}
