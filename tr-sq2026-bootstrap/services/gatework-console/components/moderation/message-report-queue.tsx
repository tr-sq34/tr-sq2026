'use client';
import { formatDateTime } from '@/lib/api-client';
import {
  MODERATION_ACTION_LABELS, REPORT_CATEGORY_LABELS, REPORT_STATUS_LABELS,
  type ReportDetail, type ReportSummary,
} from '@/lib/moderation-labels';
import { DetailFacts, DetailHistory, ReportQueue } from './report-queue';
import { cn } from '@/lib/cn';

/**
 * Messaging reports: everything specific to a private message or a group thread.
 * The split screen, the status tabs and the decision form live in ReportQueue.
 */
function EvidenceBubble({ message, highlighted }: { message: { senderId: string | null; body: string; sentAt: string }; highlighted?: boolean }) {
  return (
    <div className={cn('rounded-lg border p-3', highlighted ? 'border-danger/40 bg-danger-soft' : 'border-hairline bg-canvas')}>
      <p className="text-[11px] tracking-wide text-ink-faint uppercase">
        {message.senderId?.slice(0, 8) ?? 'bilinmiyor'} · {formatDateTime(message.sentAt)}
      </p>
      <p className="mt-1 text-sm break-words whitespace-pre-wrap text-ink">{message.body}</p>
    </div>
  );
}

const scopeLabel = (scope: string, groupName: string | null) => (scope === 'group' ? `Grup · ${groupName ?? '—'}` : 'Özel mesaj');

export function MessageReportQueue({ initialReports, canAct }: { initialReports: ReportSummary[]; canAct: boolean }) {
  return (
    <ReportQueue<ReportSummary, ReportDetail>
      initialReports={initialReports}
      canAct={canAct}
      endpoint="/api/moderation/reports"
      emptyLabel="Bu filtrede şikâyet yok."
      rowSubtitle={(report) => `${scopeLabel(report.scope, report.groupName)} · ${formatDateTime(report.createdAt)}`}
      actions={[
        { value: 'dismiss', label: 'Kural ihlali yok — reddet' },
        { value: 'remove_message', label: 'Mesajı kaldır' },
        { value: 'restrict_user', label: 'Kullanıcıyı kısıtla', needsRestriction: true },
        { value: 'remove_from_group', label: 'Gruptan çıkar' },
      ]}
      restrictionLabel="Kısıtlama türü"
      removeWithRestriction={{ field: 'removeMessage', label: 'Kısıtlamayla birlikte şikâyet edilen mesajı da kaldır' }}
      renderDetail={(detail) => (
        <>
          <DetailFacts
            rows={[
              ['Şikâyet eden', detail.reporterName ?? detail.reporterId.slice(0, 8)],
              ['Şikâyet edilen', detail.reportedUserName ?? detail.reportedUserId?.slice(0, 8) ?? '—'],
              ['Kapsam', scopeLabel(detail.scope, detail.groupName)],
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
              Bu kullanıcıda etkin kısıtlama var: {detail.activeRestriction.restriction === 'suspended' ? 'askıya alınmış' : 'susturulmuş'}
              {detail.activeRestriction.expiresAt ? ` · ${formatDateTime(detail.activeRestriction.expiresAt)} tarihine kadar` : ' · süresiz'}
            </p>
          )}

          <h3 className="mt-6 text-xs font-medium tracking-wide text-ink-faint uppercase">
            Kanıt {detail.evidence.capturedAt ? `· ${formatDateTime(detail.evidence.capturedAt)} tarihinde alındı` : '· zaman bilgisi yok'}
          </h3>
          <div className="mt-2 grid gap-2">
            {detail.evidence.unavailable && (
              <p className="rounded-lg border border-warning/30 bg-warning-soft p-3 text-sm text-warning">
                Kanıt kopyası alınamadı. Karar, şikâyetin kendisi ve kullanıcı geçmişi üzerinden verilmelidir.
              </p>
            )}
            {detail.evidence.kind === 'thread' && (
              <p className="rounded-lg border border-hairline bg-canvas p-3 text-sm text-ink-faint">
                Tek bir mesaj değil, konuşmanın tamamı şikâyet edildi.
              </p>
            )}
            {(detail.evidence.before ?? []).map((item) => <EvidenceBubble key={item.eventId} message={item} />)}
            {detail.evidence.reported && <EvidenceBubble message={detail.evidence.reported} highlighted />}
            {(detail.evidence.after ?? []).map((item) => <EvidenceBubble key={item.eventId} message={item} />)}
          </div>

          <DetailHistory
            title="Aynı kullanıcı hakkındaki diğer şikâyetler"
            items={detail.priorReports.map((prior) => ({
              key: prior.id,
              text: `${formatDateTime(prior.createdAt)} · ${REPORT_CATEGORY_LABELS[prior.category] ?? prior.category} · ${REPORT_STATUS_LABELS[prior.status] ?? prior.status}`,
            }))}
          />
          <DetailHistory
            title="Denetim kaydı"
            items={detail.actions.map((action, index) => ({
              key: `${action.action}-${index}`,
              text: `${formatDateTime(action.createdAt)} · ${MODERATION_ACTION_LABELS[action.action] ?? action.action} · ${action.reason}`,
            }))}
          />
        </>
      )}
    />
  );
}
