'use client';
import { formatDateTime } from '@/lib/api-client';
import { REPORT_CATEGORY_LABELS, REPORT_STATUS_LABELS } from '@/lib/moderation-labels';
import {
  CONTENT_ACTION_LABELS, CONTENT_STATE_LABELS, CONTENT_TARGET_LABELS,
  type ContentReportDetail, type ContentReportSummary,
} from '@/lib/content-moderation-labels';
import { Badge } from '@/components/ui/badge';
import { DetailFacts, DetailHistory, ReportQueue } from './report-queue';

/** Feed reports: a post, a comment or a story, frozen at the moment it was reported. */
export function ContentReportQueue({ initialReports, canAct }: { initialReports: ContentReportSummary[]; canAct: boolean }) {
  return (
    <ReportQueue<ContentReportSummary, ContentReportDetail>
      initialReports={initialReports}
      canAct={canAct}
      endpoint="/api/moderation/content/reports"
      emptyLabel="Bu filtrede içerik şikâyeti yok."
      rowSubtitle={(report) => `${CONTENT_TARGET_LABELS[report.targetType] ?? report.targetType} · ${formatDateTime(report.createdAt)}`}
      actions={[
        { value: 'dismiss', label: 'Kural ihlali yok — reddet' },
        { value: 'remove_content', label: 'İçeriği kaldır' },
        { value: 'restrict_author', label: 'Yazarı kısıtla', needsRestriction: true },
      ]}
      restrictionLabel="Kısıtlama türü"
      removeWithRestriction={{ field: 'removeContent', label: 'Kısıtlamayla birlikte şikâyet edilen içeriği de kaldır' }}
      renderDetail={(detail) => {
        const gone = ['removed', 'deleted', 'expired'].includes(detail.targetState);
        return (
          <>
            <div className="mt-2">
              <Badge tone="neutral">{CONTENT_TARGET_LABELS[detail.targetType] ?? detail.targetType}</Badge>
            </div>
            <DetailFacts
              rows={[
                ['Şikâyet eden', detail.reporterName ?? detail.reporterId.slice(0, 8)],
                ['İçeriğin sahibi', detail.reportedUserName ?? detail.reportedUserId.slice(0, 8)],
                ['İçeriğin şu anki durumu', CONTENT_STATE_LABELS[detail.targetState] ?? detail.targetState],
                ['Son işlem tarihi', formatDateTime(detail.dueAt)],
              ]}
            />

            {detail.note && (
              <p className="mt-4 rounded-lg border border-hairline bg-canvas p-3 text-sm text-ink-muted">
                <span className="text-ink-faint">Kullanıcının açıklaması: </span>{detail.note}
              </p>
            )}
            {detail.activeRestriction && (
              <p className="mt-4 rounded-lg border border-warning/30 bg-warning-soft p-3 text-sm text-warning">
                Bu kullanıcıda etkin kısıtlama var: {detail.activeRestriction === 'suspended' ? 'askıya alınmış' : 'susturulmuş'}
              </p>
            )}

            <h3 className="mt-6 text-xs font-medium tracking-wide text-ink-faint uppercase">
              Kanıt {detail.evidence.createdAt ? `· içerik ${formatDateTime(detail.evidence.createdAt)} tarihinde paylaşılmış` : '· zaman bilgisi yok'}
            </h3>
            {/* The snapshot, not the live row. An author deleting the post a
                second after the report was filed must not empty the case file. */}
            <div className="mt-2 rounded-lg border border-danger/40 bg-danger-soft p-3">
              {detail.evidence.body
                ? <p className="text-sm break-words whitespace-pre-wrap text-ink">{detail.evidence.body}</p>
                : <p className="text-sm text-ink-muted">Bu içerik metin taşımıyor.</p>}
              {(detail.evidence.mediaIds?.length ?? 0) > 0 && <p className="mt-2 text-xs text-ink-muted">Ekli medya: {detail.evidence.mediaIds!.join(', ')}</p>}
              {detail.evidence.mediaId && <p className="mt-2 text-xs text-ink-muted">Medya: {detail.evidence.mediaId}</p>}
              {detail.evidence.postId && <p className="mt-2 text-xs text-ink-muted">Bağlı paylaşım: {detail.evidence.postId}</p>}
            </div>
            {gone && (
              <p className="mt-2 text-xs text-ink-faint">
                İçerik artık yayında değil ({CONTENT_STATE_LABELS[detail.targetState] ?? detail.targetState}); yukarıdaki metin şikâyet anında alınan kopyadır.
              </p>
            )}

            <DetailHistory
              title="Aynı kullanıcı hakkındaki diğer şikâyetler"
              items={detail.authorHistory.map((prior) => ({
                key: prior.id,
                text: `${formatDateTime(prior.createdAt)} · ${REPORT_CATEGORY_LABELS[prior.category] ?? prior.category} · ${REPORT_STATUS_LABELS[prior.status] ?? prior.status}`,
              }))}
            />
            <DetailHistory
              title="Denetim kaydı"
              items={detail.actions.map((action, index) => ({
                key: `${action.action}-${index}`,
                text: `${formatDateTime(action.createdAt)} · ${CONTENT_ACTION_LABELS[action.action] ?? action.action} · ${action.reason}`,
              }))}
            />
          </>
        );
      }}
    />
  );
}
