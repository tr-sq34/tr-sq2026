'use client';
import dynamic from 'next/dynamic';
import type { ApexOptions } from 'apexcharts';

/**
 * The weekly trend line.
 *
 * ApexCharts touches `window` on import, so it is loaded client-side only; the
 * placeholder holds the same height so the page does not jump when it arrives.
 *
 * Missing weeks are `null`, never `0`. The two services answer with their own
 * week lists, and a service that has no row for a week has not told us that
 * nothing happened - it has told us nothing. Apex draws a gap for null and a
 * point on the floor for zero, and those are different claims.
 */
const ReactApexChart = dynamic(() => import('react-apexcharts'), {
  ssr: false,
  loading: () => <div className="h-72 animate-pulse rounded-lg bg-surface-raised" />,
});

export type TrendSeries = { name: string; data: (number | null)[] };

// Straight from the theme tokens in globals.css; Apex needs literal colours and
// cannot read a CSS variable through a class.
const PALETTE = ['#6c5ce7', '#16a085', '#e8a33a', '#e87393', '#a08ff3'];

export function TrendChart({ categories, series, height = 300 }: { categories: string[]; series: TrendSeries[]; height?: number }) {
  const options: ApexOptions = {
    chart: {
      type: 'line',
      toolbar: { show: false },
      zoom: { enabled: false },
      background: 'transparent',
      fontFamily: 'inherit',
      animations: { enabled: false },
    },
    theme: { mode: 'dark' },
    colors: PALETTE,
    stroke: { curve: 'smooth', width: 2.5 },
    markers: { size: 3, strokeWidth: 0, hover: { size: 5 } },
    dataLabels: { enabled: false },
    grid: { borderColor: '#2a2740', strokeDashArray: 4, padding: { left: 4, right: 8 } },
    xaxis: {
      categories,
      axisBorder: { show: false },
      axisTicks: { show: false },
      labels: { style: { colors: '#6f6b80', fontSize: '11px' } },
      tooltip: { enabled: false },
    },
    yaxis: {
      labels: {
        style: { colors: '#6f6b80', fontSize: '11px' },
        formatter: (value: number) => Math.round(value).toLocaleString('tr-TR'),
      },
    },
    legend: {
      position: 'top',
      horizontalAlign: 'left',
      fontSize: '12px',
      labels: { colors: '#a5a1b5' },
      markers: { size: 6 },
      itemMargin: { horizontal: 10 },
    },
    tooltip: {
      theme: 'dark',
      // A gap is a gap: the tooltip must not invent a zero for a week the
      // service did not report.
      y: { formatter: (value: number | null) => (value === null ? 'veri yok' : value.toLocaleString('tr-TR')) },
    },
  };

  return <ReactApexChart type="line" height={height} options={options} series={series} />;
}
