'use client';
import { useMemo, useState } from 'react';
import {
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getSortedRowModel,
  useReactTable,
  type ColumnDef,
  type SortingState,
} from '@tanstack/react-table';
import { ArrowDown, ArrowUp, ChevronsUpDown, Search } from 'lucide-react';
import { cn } from '@/lib/cn';

/**
 * The console's table.
 *
 * Every desk rendered its rows as a stack of `<article>` cards, which reads
 * fine at five rows and stops working at fifty: nothing lines up, so nothing
 * can be compared or sorted, and an operator scanning for the oldest open
 * report had to read every card. `@tanstack/react-table` was already a
 * dependency for exactly this and was never used.
 *
 * Filtering and sorting are client-side and deliberately so - these lists are a
 * page of rows an API already scoped and paginated, not the whole table. A
 * search box that silently only searches the page you are on would be a lie, so
 * `resultLabel` always states what was matched against what.
 */
export function DataTable<T>({
  columns,
  rows,
  onRowClick,
  searchPlaceholder,
  emptyLabel,
  toolbar,
  rowKey,
  isRowUrgent,
}: {
  columns: ColumnDef<T, unknown>[];
  rows: T[];
  onRowClick?: (row: T) => void;
  searchPlaceholder?: string;
  emptyLabel: string;
  toolbar?: React.ReactNode;
  rowKey: (row: T) => string;
  isRowUrgent?: (row: T) => boolean;
}) {
  const [sorting, setSorting] = useState<SortingState>([]);
  const [query, setQuery] = useState('');

  const table = useReactTable({
    data: rows,
    columns,
    state: { sorting, globalFilter: query },
    onSortingChange: setSorting,
    onGlobalFilterChange: setQuery,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getRowId: (row) => rowKey(row),
  });

  const visible = table.getRowModel().rows;
  const filtered = query.trim().length > 0;
  const resultLabel = useMemo(
    () => (filtered ? `${rows.length} satırın ${visible.length} tanesi eşleşti` : `${rows.length} satır`),
    [filtered, rows.length, visible.length],
  );

  return (
    <div className="rounded-card border border-hairline bg-surface">
      {(searchPlaceholder || toolbar) && (
        <div className="flex flex-wrap items-center justify-between gap-3 border-b border-hairline p-4">
          {searchPlaceholder && (
            <div className="relative min-w-56 flex-1">
              <Search size={15} className="absolute top-1/2 left-3 -translate-y-1/2 text-ink-faint" />
              <input
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder={searchPlaceholder}
                aria-label={searchPlaceholder}
                className="w-full rounded-lg border border-hairline bg-canvas py-2 pr-3 pl-9 text-sm outline-none transition placeholder:text-ink-faint focus:border-brand-400"
              />
            </div>
          )}
          <div className="flex items-center gap-3">
            <span className="text-xs text-ink-faint">{resultLabel}</span>
            {toolbar}
          </div>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full min-w-max border-collapse text-sm">
          <thead>
            {table.getHeaderGroups().map((group) => (
              <tr key={group.id} className="border-b border-hairline">
                {group.headers.map((header) => {
                  const sortable = header.column.getCanSort();
                  const direction = header.column.getIsSorted();
                  return (
                    <th key={header.id} className="px-4 py-3 text-left text-xs font-medium tracking-wide text-ink-faint uppercase">
                      {header.isPlaceholder ? null : sortable ? (
                        <button
                          type="button"
                          onClick={header.column.getToggleSortingHandler()}
                          className="inline-flex items-center gap-1.5 transition hover:text-ink"
                        >
                          {flexRender(header.column.columnDef.header, header.getContext())}
                          {direction === 'asc' ? <ArrowUp size={12} /> : direction === 'desc' ? <ArrowDown size={12} /> : <ChevronsUpDown size={12} className="opacity-40" />}
                        </button>
                      ) : (
                        flexRender(header.column.columnDef.header, header.getContext())
                      )}
                    </th>
                  );
                })}
              </tr>
            ))}
          </thead>
          <tbody>
            {visible.map((row) => (
              <tr
                key={row.id}
                onClick={onRowClick ? () => onRowClick(row.original) : undefined}
                // A row that opens a panel has to be reachable without a mouse;
                // the desks this replaces put the only affordance on hover.
                tabIndex={onRowClick ? 0 : undefined}
                role={onRowClick ? 'button' : undefined}
                onKeyDown={
                  onRowClick
                    ? (event) => {
                        if (event.key === 'Enter' || event.key === ' ') {
                          event.preventDefault();
                          onRowClick(row.original);
                        }
                      }
                    : undefined
                }
                className={cn(
                  'border-b border-hairline/60 last:border-0',
                  onRowClick && 'cursor-pointer transition hover:bg-surface-raised',
                  isRowUrgent?.(row.original) && 'bg-danger-soft/40',
                )}
              >
                {row.getVisibleCells().map((cell) => (
                  <td key={cell.id} className="px-4 py-3 align-middle text-ink-muted">
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </td>
                ))}
              </tr>
            ))}
            {visible.length === 0 && (
              <tr>
                <td colSpan={columns.length} className="px-4 py-12 text-center text-sm text-ink-faint">
                  {filtered ? `"${query}" ile eşleşen satır yok.` : emptyLabel}
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

export type { ColumnDef };
