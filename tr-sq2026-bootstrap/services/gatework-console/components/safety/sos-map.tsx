'use client';
import { useState } from 'react';
import { Minus, Plus, MapPin } from 'lucide-react';
import { Button } from '@/components/ui/button';

/**
 * The map for an unsealed SOS point.
 *
 * Two rules shape it. First, no tile is requested until the operator asks:
 * an embedded map that loads with the panel would hand a frightened member's
 * coordinates to a tile provider every time anybody opened the screen, whether
 * they looked or not. Second, no map library and no iframe - the tiles are plain
 * `<img>` elements positioned by the same Web Mercator arithmetic every slippy
 * map uses, so nothing on this page can call home with more than the nine tiles
 * that were asked for.
 *
 * The accuracy circle is drawn to scale rather than as decoration. "±800 m" and
 * "±8 m" are different situations, and a fixed dot makes them look identical.
 */
const TILE = 256;
const MIN_ZOOM = 12;
const MAX_ZOOM = 18;

const lonToX = (lon: number, zoom: number) => ((lon + 180) / 360) * 2 ** zoom;
const latToY = (lat: number, zoom: number) => {
  const rad = (lat * Math.PI) / 180;
  return ((1 - Math.log(Math.tan(rad) + 1 / Math.cos(rad)) / Math.PI) / 2) * 2 ** zoom;
};
const metresPerPixel = (lat: number, zoom: number) => (156543.03392 * Math.cos((lat * Math.PI) / 180)) / 2 ** zoom;

export function SosMap({ latitude, longitude, accuracyMeters }: { latitude: number; longitude: number; accuracyMeters: number | null }) {
  const [zoom, setZoom] = useState(16);
  const [loaded, setLoaded] = useState(false);

  const fx = lonToX(longitude, zoom);
  const fy = latToY(latitude, zoom);
  const originX = Math.floor(fx) - 1;
  const originY = Math.floor(fy) - 1;
  // Where the point sits inside the 3x3 grid of tiles, in pixels.
  const pointX = (fx - originX) * TILE;
  const pointY = (fy - originY) * TILE;
  const radius = accuracyMeters !== null ? accuracyMeters / metresPerPixel(latitude, zoom) : null;

  const osmLink = `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=${zoom}/${latitude}/${longitude}`;

  if (!loaded) {
    return (
      <div className="rounded-card border border-dashed border-hairline bg-canvas px-5 py-8 text-center">
        <MapPin size={22} className="mx-auto text-ink-faint" />
        <p className="mt-3 text-sm font-medium text-ink">Harita karesi henüz yüklenmedi.</p>
        <p className="mx-auto mt-1.5 max-w-sm text-xs text-ink-faint">
          Yüklersen bu koordinat harita sunucusuna (OpenStreetMap) gider. Kendiliğinden yüklenmez; bu yüzden bakmadığın bir çağrının konumu dışarı çıkmaz.
        </p>
        <Button type="button" size="sm" variant="secondary" className="mt-4" onClick={() => setLoaded(true)}>
          Harita karesini yükle
        </Button>
      </div>
    );
  }

  return (
    <div className="overflow-hidden rounded-card border border-hairline bg-canvas">
      <div className="relative h-64 overflow-hidden bg-surface-raised">
        <div
          className="absolute"
          style={{ width: TILE * 3, height: TILE * 3, left: `calc(50% - ${pointX}px)`, top: `calc(50% - ${pointY}px)` }}
        >
          {[0, 1, 2].map((row) =>
            [0, 1, 2].map((col) => (
              // eslint-disable-next-line @next/next/no-img-element
              <img
                key={`${zoom}-${row}-${col}`}
                src={`https://tile.openstreetmap.org/${zoom}/${originX + col}/${originY + row}.png`}
                alt=""
                width={TILE}
                height={TILE}
                className="absolute"
                style={{ left: col * TILE, top: row * TILE }}
              />
            )),
          )}
          {radius !== null && radius > 4 && (
            <span
              className="absolute rounded-full border-2 border-danger/70 bg-danger/15"
              style={{ width: radius * 2, height: radius * 2, left: pointX - radius, top: pointY - radius }}
            />
          )}
          <span
            className="absolute size-3 rounded-full border-2 border-white bg-danger shadow"
            style={{ left: pointX - 6, top: pointY - 6 }}
          />
        </div>

        <div className="absolute top-2 right-2 flex flex-col gap-1">
          <Button type="button" size="icon" variant="secondary" aria-label="Yakınlaştır" disabled={zoom >= MAX_ZOOM} onClick={() => setZoom((z) => Math.min(MAX_ZOOM, z + 1))}>
            <Plus size={15} />
          </Button>
          <Button type="button" size="icon" variant="secondary" aria-label="Uzaklaştır" disabled={zoom <= MIN_ZOOM} onClick={() => setZoom((z) => Math.max(MIN_ZOOM, z - 1))}>
            <Minus size={15} />
          </Button>
        </div>
      </div>

      <div className="flex flex-wrap items-center justify-between gap-2 border-t border-hairline px-4 py-2.5 text-xs text-ink-faint">
        <span className="tabular-nums text-ink-muted">{latitude.toFixed(5)}, {longitude.toFixed(5)}</span>
        <span>
          {accuracyMeters !== null ? `±${accuracyMeters} m · ` : ''}
          <a className="text-brand-300 underline" target="_blank" rel="noreferrer" href={osmLink}>OpenStreetMap’te aç</a>
          {' · '}© OpenStreetMap katkıcıları
        </span>
      </div>
    </div>
  );
}
