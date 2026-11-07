/* Segnavia — diario dei trekking. Vanilla JS, dati in IndexedDB sul dispositivo. */
(() => {
'use strict';

// ---------------------------------------------------------------- utils
const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const nf0 = new Intl.NumberFormat('it-IT', { maximumFractionDigits: 0 });
const nf1 = new Intl.NumberFormat('it-IT', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const km = (m) => nf1.format((m || 0) / 1000);
const mt = (m) => nf0.format(Math.round(m || 0));
const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 8);
const MONTHS = ['gen', 'feb', 'mar', 'apr', 'mag', 'giu', 'lug', 'ago', 'set', 'ott', 'nov', 'dic'];
const fmtDate = (iso, long) => {
  if (!iso) return '';
  const d = new Date(iso + (iso.length === 10 ? 'T12:00:00' : ''));
  return d.toLocaleDateString('it-IT', long ? { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' } : { day: 'numeric', month: 'short', year: 'numeric' });
};
const fmtDur = (sec) => {
  if (!sec) return '–';
  const h = Math.floor(sec / 3600), m = Math.round((sec % 3600) / 60);
  return h ? `${h}h ${String(m).padStart(2, '0')}` : `${m} min`;
};
const todayISO = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
const DIFF = {
  T: { name: 'Turistico', short: 'Turistico' },
  E: { name: 'Escursionistico', short: 'Escurs.' },
  EE: { name: 'Escursionisti esperti', short: 'Esperti' },
  EEA: { name: 'Esperti con attrezzatura', short: 'Attrezz.' },
};
const ICON = {
  back: '<svg viewBox="0 0 24 24"><path d="M15 5l-7 7 7 7"/></svg>',
  share: '<svg viewBox="0 0 24 24"><path d="M12 3v12M7 8l5-5 5 5"/><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6"/></svg>',
  edit: '<svg viewBox="0 0 24 24"><path d="M4 20h4L19 9l-4-4L4 16v4Z"/></svg>',
  trash: '<svg viewBox="0 0 24 24"><path d="M4 7h16M9 7V4h6v3M6 7l1 13h10l1-13"/></svg>',
  file: '<svg viewBox="0 0 24 24"><path d="M14 3H6v18h12V7l-4-4Z"/><path d="M14 3v4h4M9 13h6M9 17h6"/></svg>',
  pen: '<svg viewBox="0 0 24 24"><path d="M4 20h16M6 16l10-10 2 2-10 10H6v-2Z"/></svg>',
  rec: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>',
  heart: '<svg viewBox="0 0 24 24"><path d="M12 20s-7-4.5-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.5-7 10-7 10Z"/></svg>',
  chev: '<svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7"/></svg>',
  search: '<svg viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg>',
  gpx: '<svg viewBox="0 0 24 24"><path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 19h14"/></svg>',
  locate: '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></svg>',
};

function toast(msg, ms = 2600) {
  const t = $('#toast'); t.textContent = msg; t.hidden = false;
  clearTimeout(toast._t); toast._t = setTimeout(() => (t.hidden = true), ms);
}
const ls = {
  get(k, d) { try { const v = localStorage.getItem('segnavia:' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('segnavia:' + k, JSON.stringify(v)); } catch {} },
  del(k) { try { localStorage.removeItem('segnavia:' + k); } catch {} },
};

// ---------------------------------------------------------------- storage (IndexedDB, fallback in memoria)
const DB = (() => {
  let dbp = null; const mem = { treks: new Map(), photos: new Map() };
  function open() {
    if (dbp) return dbp;
    dbp = new Promise((res) => {
      try {
        const r = indexedDB.open('segnavia', 1);
        r.onupgradeneeded = () => {
          const db = r.result;
          db.createObjectStore('treks', { keyPath: 'id' });
          const p = db.createObjectStore('photos', { keyPath: 'id' });
          p.createIndex('trekId', 'trekId');
        };
        r.onsuccess = () => res(r.result);
        r.onerror = () => res(null);
      } catch { res(null); }
    });
    return dbp;
  }
  const tx = async (store, mode, fn) => {
    const db = await open();
    if (!db) return fn(null, mem[store]);
    return new Promise((res, rej) => {
      const t = db.transaction(store, mode); const s = t.objectStore(store);
      let out; const r = fn(s); if (r) r.onsuccess = () => (out = r.result);
      t.oncomplete = () => res(out); t.onerror = () => rej(t.error);
    });
  };
  return {
    async all() { const v = await tx('treks', 'readonly', (s, m) => s ? s.getAll() : [...m.values()]); return Array.isArray(v) ? v : []; },
    get: (id) => tx('treks', 'readonly', (s, m) => s ? s.get(id) : m.get(id)),
    put: (t) => tx('treks', 'readwrite', (s, m) => s ? s.put(t) : m.set(t.id, t)),
    del: (id) => tx('treks', 'readwrite', (s, m) => s ? s.delete(id) : m.delete(id)),
    async photos(trekId) {
      const v = await tx('photos', 'readonly', (s, m) => s ? s.index('trekId').getAll(trekId) : [...m.values()].filter(p => p.trekId === trekId));
      return (Array.isArray(v) ? v : []).sort((a, b) => a.order - b.order);
    },
    allPhotos: async () => { const v = await tx('photos', 'readonly', (s, m) => s ? s.getAll() : [...m.values()]); return Array.isArray(v) ? v : []; },
    putPhoto: (p) => tx('photos', 'readwrite', (s, m) => s ? s.put(p) : m.set(p.id, p)),
    delPhoto: (id) => tx('photos', 'readwrite', (s, m) => s ? s.delete(id) : m.delete(id)),
    persist() { try { navigator.storage?.persist?.(); } catch {} },
  };
})();

// ---------------------------------------------------------------- geo
const R = 6371008.8, rad = Math.PI / 180;
function dist(a, b) {
  const dLat = (b[0] - a[0]) * rad, dLon = (b[1] - a[1]) * rad;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a[0] * rad) * Math.cos(b[0] * rad) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}
function cumDist(pts) { const c = [0]; for (let i = 1; i < pts.length; i++) c.push(c[i - 1] + dist(pts[i - 1], pts[i])); return c; }
function smoothEle(pts, w = 3) {
  const e = pts.map(p => p[2]);
  return e.map((v, i) => {
    if (v == null) return null; let s = 0, n = 0;
    for (let j = Math.max(0, i - w); j <= Math.min(e.length - 1, i + w); j++) if (e[j] != null) { s += e[j]; n++; }
    return s / n;
  });
}
function computeStats(pts) {
  const out = { distance: 0, gain: 0, loss: 0, maxEle: null, minEle: null, duration: 0, moving: 0, start: null, end: null };
  if (!pts || pts.length < 2) return out;
  const c = cumDist(pts); out.distance = c[c.length - 1];
  const e = smoothEle(pts); let ref = null; const TH = 4;
  for (const v of e) {
    if (v == null) continue;
    if (out.maxEle == null || v > out.maxEle) out.maxEle = v;
    if (out.minEle == null || v < out.minEle) out.minEle = v;
    if (ref == null) { ref = v; continue; }
    const d = v - ref; if (d >= TH) { out.gain += d; ref = v; } else if (d <= -TH) { out.loss -= d; ref = v; }
  }
  const raw = pts.map(p => p[2]).filter(v => v != null);
  if (raw.length) { out.maxEle = Math.max(out.maxEle, ...raw.slice(0, 50000)); }
  const t0 = pts[0][3], t1 = pts[pts.length - 1][3];
  if (t0 && t1 && t1 > t0) {
    out.start = t0; out.end = t1; out.duration = (t1 - t0) / 1000;
    for (let i = 1; i < pts.length; i++) {
      const dt = (pts[i][3] - pts[i - 1][3]) / 1000; if (!(dt > 0)) continue;
      const v = (c[i] - c[i - 1]) / dt; if (v > 0.25 && dt < 600) out.moving += dt;
    }
  }
  return out;
}
function downsample(pts, max = 2500) {
  if (pts.length <= max) return pts;
  // prima per distanza minima, poi uniforme
  const out = [pts[0]]; let last = pts[0];
  for (let i = 1; i < pts.length - 1; i++) if (dist(last, pts[i]) >= 6) { out.push(pts[i]); last = pts[i]; }
  out.push(pts[pts.length - 1]);
  if (out.length <= max) return out;
  const step = out.length / max, res = [];
  for (let i = 0; i < max - 1; i++) res.push(out[Math.floor(i * step)]);
  res.push(out[out.length - 1]); return res;
}
const roundPt = (p) => [Math.round(p[0] * 1e6) / 1e6, Math.round(p[1] * 1e6) / 1e6, p[2] == null ? null : Math.round(p[2] * 10) / 10, p[3] || null];
function bbox(pts) {
  let a = 90, b = 180, c = -90, d = -180;
  for (const p of pts) { if (p[0] < a) a = p[0]; if (p[0] > c) c = p[0]; if (p[1] < b) b = p[1]; if (p[1] > d) d = p[1]; }
  return [a, b, c, d];
}
// proiezione equirettangolare corretta per latitudine, per thumbnail e card
function project(pts, w, h, pad) {
  const [s, wst, n, e] = bbox(pts); const k = Math.cos(((s + n) / 2) * rad);
  const dx = Math.max((e - wst) * k, 1e-6), dy = Math.max(n - s, 1e-6);
  const sc = Math.min((w - 2 * pad) / dx, (h - 2 * pad) / dy);
  const ox = (w - dx * sc) / 2, oy = (h - dy * sc) / 2;
  return pts.map(p => [ox + (p[1] - wst) * k * sc, oy + (n - p[0]) * sc]);
}

// ---------------------------------------------------------------- parser GPX / TCX
function parseXML(text) {
  const doc = new DOMParser().parseFromString(text, 'application/xml');
  if (doc.getElementsByTagName('parsererror').length) throw new Error('File non leggibile');
  return doc;
}
const tag = (el, name) => el.getElementsByTagNameNS('*', name);
function parseGPX(text) {
  const doc = parseXML(text);
  let nodes = [...tag(doc, 'trkpt')]; if (!nodes.length) nodes = [...tag(doc, 'rtept')];
  const pts = nodes.map(n => {
    const ele = tag(n, 'ele')[0], time = tag(n, 'time')[0];
    return [parseFloat(n.getAttribute('lat')), parseFloat(n.getAttribute('lon')), ele ? parseFloat(ele.textContent) : null, time ? Date.parse(time.textContent) || null : null];
  }).filter(p => isFinite(p[0]) && isFinite(p[1]));
  const trk = tag(doc, 'trk')[0];
  const nameEl = (trk && [...trk.children].find(c => c.localName === 'name')) || [...(tag(doc, 'metadata')[0]?.children || [])].find(c => c.localName === 'name');
  const typeEl = trk && [...trk.children].find(c => c.localName === 'type');
  return { name: nameEl?.textContent?.trim() || '', type: typeEl?.textContent?.trim() || '', points: pts };
}
function parseTCX(text) {
  const doc = parseXML(text);
  const pts = [...tag(doc, 'Trackpoint')].map(n => {
    const la = tag(n, 'LatitudeDegrees')[0], lo = tag(n, 'LongitudeDegrees')[0], el = tag(n, 'AltitudeMeters')[0], t = tag(n, 'Time')[0];
    return la && lo ? [parseFloat(la.textContent), parseFloat(lo.textContent), el ? parseFloat(el.textContent) : null, t ? Date.parse(t.textContent) || null : null] : null;
  }).filter(Boolean);
  const act = tag(doc, 'Activity')[0];
  return { name: tag(doc, 'Notes')[0]?.textContent?.trim() || '', type: act?.getAttribute('Sport') || '', points: pts };
}
function parseTrackFile(name, text) {
  const lower = name.toLowerCase();
  const r = lower.endsWith('.tcx') || text.includes('<TrainingCenterDatabase') ? parseTCX(text) : parseGPX(text);
  if (r.points.length < 2) throw new Error(`${name}: nessuna traccia trovata`);
  return r;
}
function cleanName(n, file) {
  if (n && !/^(route|track|activity|percorso)[\s_-]*\d*/i.test(n) && !/^\d{4}-\d{2}-\d{2}/.test(n)) return n;
  return '';
}
function buildDraft(parsed, fileName, source) {
  const pts = downsample(parsed.points).map(roundPt);
  const st = computeStats(parsed.points);
  const startT = parsed.points[0][3];
  return {
    id: uid(), name: cleanName(parsed.name, fileName), location: '', region: '',
    date: startT ? new Date(startT - new Date(startT).getTimezoneOffset() * 60000).toISOString().slice(0, 10) : todayISO(),
    startTime: startT || null, duration: Math.round(st.duration), moving: Math.round(st.moving),
    distance: Math.round(st.distance), gain: Math.round(st.gain), loss: Math.round(st.loss),
    maxEle: st.maxEle == null ? null : Math.round(st.maxEle), minEle: st.minEle == null ? null : Math.round(st.minEle),
    difficulty: st.gain > 1100 ? 'EE' : 'E', rating: 0, notes: '', companions: '', track: pts, source, fileName,
    createdAt: Date.now(),
  };
}

// ---------------------------------------------------------------- GPX export
function toGPX(t) {
  const pts = (t.track || []).map(p => `<trkpt lat="${p[0]}" lon="${p[1]}">${p[2] != null ? `<ele>${p[2]}</ele>` : ''}${p[3] ? `<time>${new Date(p[3]).toISOString()}</time>` : ''}</trkpt>`).join('\n      ');
  return `<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Segnavia" xmlns="http://www.topografix.com/GPX/1/1">
  <metadata><name>${esc(t.name)}</name><time>${new Date(t.startTime || Date.parse(t.date)).toISOString()}</time></metadata>
  <trk><name>${esc(t.name)}</name><type>hiking</type><desc>${esc([t.location, t.region].filter(Boolean).join(', '))}</desc>
    <trkseg>
      ${pts}
    </trkseg>
  </trk>
</gpx>`;
}
const slug = (s) => (s || 'trekking').normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/gi, '-').replace(/^-|-$/g, '').toLowerCase();

// ---------------------------------------------------------------- reverse geocoding (OpenStreetMap Nominatim)
async function reverseGeocode(lat, lon) {
  try {
    const ctl = new AbortController(); const to = setTimeout(() => ctl.abort(), 6000);
    const r = await fetch(`https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lon}&zoom=14&accept-language=it`, { signal: ctl.signal });
    clearTimeout(to); if (!r.ok) return null; const j = await r.json(); const a = j.address || {};
    return { location: a.village || a.town || a.city || a.hamlet || a.municipality || a.county || '', region: a.state || a.region || a.country || '' };
  } catch { return null; }
}

// ---------------------------------------------------------------- dati di esempio
function synthTrack(wps, startISO, outAndBack, seed) {
  let s = seed; const rnd = () => ((s = (s * 9301 + 49297) % 233280) / 233280);
  let route = wps.slice(); if (outAndBack) route = route.concat(wps.slice(0, -1).reverse());
  const pts = [];
  for (let i = 0; i < route.length - 1; i++) {
    const a = route[i], b = route[i + 1]; const d = dist(a, b); const n = Math.max(2, Math.round(d / 20));
    const steep = Math.abs(b[2] - a[2]) / Math.max(d, 1); const amp = steep > 0.15 ? 0.00028 : 0.00008; const freq = steep > 0.15 ? 9 : 3;
    const nx = -(b[1] - a[1]), ny = (b[0] - a[0]); const nl = Math.hypot(nx, ny) || 1;
    for (let j = 0; j < n; j++) {
      const f = j / n; const w = Math.sin(f * Math.PI) * Math.sin(f * Math.PI * freq + i) * amp;
      pts.push([a[0] + (b[0] - a[0]) * f + (nx / nl) * w * 0.7, a[1] + (b[1] - a[1]) * f + (ny / nl) * w, a[2] + (b[2] - a[2]) * f + (rnd() - 0.5) * 3]);
    }
  }
  pts.push(route[route.length - 1].slice());
  // tempi con la funzione di Tobler
  let t = Date.parse(startISO);
  pts.forEach((p, i) => {
    if (i) { const d = dist(pts[i - 1], p); const sl = (p[2] - pts[i - 1][2]) / Math.max(d, 1); const v = 6 * Math.exp(-3.5 * Math.abs(sl + 0.05)) * 0.82 / 3.6; t += (d / v) * 1000; if (i % 140 === 0) t += 8 * 60000; }
    p[3] = Math.round(t);
  });
  return pts;
}
function exampleTreks() {
  const mk = (o, wps, start, oab, seed) => {
    const raw = synthTrack(wps, start, oab, seed); const d = buildDraft({ name: o.name, points: raw }, '', 'example');
    return Object.assign(d, o, { example: true });
  };
  return [
    mk({ name: 'Giro delle Tre Cime di Lavaredo', location: 'Auronzo di Cadore', region: 'Veneto', difficulty: 'E', rating: 5, companions: 'Giulia, Marco',
      notes: 'Partenza presto dal Rifugio Auronzo per evitare la folla. Luce pazzesca sulla parete nord dalla Forcella Lavaredo. Pranzo al Locatelli: canederli.' },
    [[46.6122, 12.2955, 2320], [46.6146, 12.3040, 2310], [46.6176, 12.3080, 2344], [46.6223, 12.3108, 2454], [46.6326, 12.3088, 2405], [46.6352, 12.2990, 2290], [46.6313, 12.2890, 2283], [46.6262, 12.2852, 2355], [46.6200, 12.2880, 2315], [46.6122, 12.2955, 2320]],
    '2026-08-14T07:10:00+02:00', false, 7),
    mk({ name: 'Lago di Sorapis', location: 'Cortina d\'Ampezzo', region: 'Veneto', difficulty: 'E', rating: 4, companions: '',
      notes: 'Sentiero 215 dal Passo Tre Croci. Qualche tratto attrezzato con cavo, niente di difficile. Il lago è davvero color turchese.' },
    [[46.5555, 12.2040, 1805], [46.5490, 12.2080, 1835], [46.5405, 12.2140, 1875], [46.5315, 12.2180, 1905], [46.5250, 12.2200, 1965], [46.5195, 12.2196, 1928], [46.5176, 12.2214, 1925]],
    '2026-07-05T08:30:00+02:00', true, 11),
    mk({ name: 'Rifugio Vittorio Emanuele II', location: 'Valsavarenche', region: 'Valle d\'Aosta', difficulty: 'E', rating: 4, companions: 'Luca',
      notes: 'Salita regolare da Pont, stambecchi sopra i 2400. Vista sul Ciarforon e sul ghiacciaio del Gran Paradiso.' },
    [[45.5307, 7.2009, 1960], [45.5262, 7.2045, 2080], [45.5228, 7.2112, 2230], [45.5196, 7.2160, 2380], [45.5160, 7.2214, 2530], [45.5128, 7.2268, 2650], [45.5108, 7.2306, 2732]],
    '2026-09-20T08:00:00+02:00', true, 23),
    mk({ name: 'Monte Grona', location: 'Plesio', region: 'Lombardia', difficulty: 'EE', rating: 5, companions: 'Sara',
      notes: 'Dalla Breglia al Rifugio Menaggio, poi cresta finale con passaggi esposti. Panorama su tutto il Lago di Como.' },
    [[46.0350, 9.2050, 750], [46.0385, 9.2095, 900], [46.0420, 9.2140, 1080], [46.0455, 9.2175, 1260], [46.0478, 9.2195, 1383], [46.0510, 9.2170, 1520], [46.0540, 9.2140, 1650], [46.0560, 9.2120, 1736]],
    '2025-10-12T08:45:00+02:00', true, 31),
  ];
}

// ---------------------------------------------------------------- stato
let TREKS = [];
let currentMap = null; let pendingDraft = null; let yearFilter = ls.get('year', 'tutti'); let query = '';
const sortTreks = () => TREKS.sort((a, b) => (b.date || '').localeCompare(a.date || '') || (b.startTime || 0) - (a.startTime || 0));
async function load() {
  TREKS = await DB.all();
  if (!TREKS.length && !ls.get('seeded', false)) {
    for (const t of exampleTreks()) await DB.put(t);
    ls.set('seeded', true); TREKS = await DB.all();
  }
  sortTreks();
}
async function save(t) {
  t.updatedAt = Date.now(); await DB.put(t);
  const i = TREKS.findIndex(x => x.id === t.id); if (i >= 0) TREKS[i] = t; else TREKS.push(t); sortTreks(); DB.persist();
}
async function remove(id) {
  await DB.del(id); for (const p of await DB.photos(id)) await DB.delPhoto(p.id);
  TREKS = TREKS.filter(t => t.id !== id);
}

// ---------------------------------------------------------------- mappe
const TILES = {
  topo: () => L.tileLayer('https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png', { maxZoom: 17, subdomains: 'abc', attribution: '© OpenStreetMap, SRTM · © OpenTopoMap (CC-BY-SA)' }),
  osm: () => L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© OpenStreetMap' }),
  sat: () => L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', { maxZoom: 18, attribution: 'Immagini © Esri' }),
  trails: () => L.tileLayer('https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png', { maxZoom: 18, opacity: .85, attribution: 'Sentieri © waymarkedtrails.org' }),
};
function makeMap(el, opts = {}) {
  if (currentMap) { try { currentMap.remove(); } catch {} currentMap = null; }
  const map = L.map(el, { zoomControl: false, attributionControl: true, ...opts });
  const base = { 'Topografica': TILES.topo(), 'Satellite': TILES.sat(), 'Stradale': TILES.osm() };
  const over = { 'Sentieri escursionistici': TILES.trails() };
  const pref = ls.get('baseLayer', 'Topografica'); (base[pref] || base.Topografica).addTo(map);
  if (ls.get('trails', true)) over['Sentieri escursionistici'].addTo(map);
  L.control.layers(base, over, { position: 'topright' }).addTo(map);
  L.control.zoom({ position: 'bottomright' }).addTo(map);
  map.on('baselayerchange', e => ls.set('baseLayer', e.name));
  map.on('overlayadd', () => ls.set('trails', true)); map.on('overlayremove', () => ls.set('trails', false));
  currentMap = map; return map;
}
const pin = (cls) => L.divIcon({ className: '', html: `<div class="pin ${cls}"></div>`, iconSize: [16, 16], iconAnchor: [8, 8] });
const accent = () => getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#D3222A';

// ---------------------------------------------------------------- piccoli componenti
function thumbSVG(t) {
  const pts = t.track || [];
  if (pts.length < 2) return `<svg viewBox="0 0 96 96" aria-hidden="true"><path d="M8 78 L34 40 L48 58 L64 30 L88 78 Z" fill="var(--line)"/><path d="M58 38 L64 30 L70 40" fill="none" stroke="var(--surface)" stroke-width="3"/></svg>`;
  const step = Math.max(1, Math.floor(pts.length / 160)); const s = pts.filter((_, i) => i % step === 0); s.push(pts[pts.length - 1]);
  const xy = project(s, 96, 96, 12); const d = xy.map((p, i) => (i ? 'L' : 'M') + p[0].toFixed(1) + ' ' + p[1].toFixed(1)).join('');
  const contours = [18, 32, 46, 60].map(r => `<circle cx="70" cy="26" r="${r}" fill="none" stroke="var(--line)" stroke-width="1"/>`).join('');
  return `<svg viewBox="0 0 96 96" aria-hidden="true">${contours}<path d="${d}" fill="none" stroke="var(--surface)" stroke-width="6" stroke-linejoin="round" stroke-linecap="round"/><path d="${d}" fill="none" stroke="var(--accent)" stroke-width="2.6" stroke-linejoin="round" stroke-linecap="round"/><circle cx="${xy[0][0]}" cy="${xy[0][1]}" r="3.5" fill="var(--ink)" stroke="var(--surface)" stroke-width="1.5"/></svg>`;
}
const stars = (n) => n ? `<span class="stars" aria-label="${n} su 5">${'★'.repeat(n)}<span style="color:var(--line)">${'★'.repeat(5 - n)}</span></span>` : '';
const diffTag = (d) => d ? `<span class="diff" data-d="${esc(d)}" title="${esc(DIFF[d]?.name || '')}">${esc(d)}</span>` : '';
function trekCard(t) {
  return `<a class="card trek-card" href="#trek-${t.id}">
    <div class="thumb">${thumbSVG(t)}</div>
    <div style="min-width:0">
      <div class="t-top">${diffTag(t.difficulty)}<span class="t-meta">${esc(fmtDate(t.date))}</span>${t.example ? '<span class="chip example">Esempio</span>' : ''}</div>
      <div class="t-name">${esc(t.name || 'Trekking senza nome')}</div>
      <div class="t-meta">${esc([t.location, t.region].filter(Boolean).join(' · ') || '—')}</div>
      <div class="t-stats">
        <span class="t-stat">${km(t.distance)}<small>km</small></span>
        <span class="t-stat">↑${mt(t.gain)}<small>m</small></span>
        <span class="t-stat">${fmtDur(t.moving || t.duration)}</span>
      </div>
    </div></a>`;
}
function totalsFor(list) {
  return list.reduce((a, t) => (a.n++, a.d += t.distance || 0, a.g += t.gain || 0, a.s += t.moving || t.duration || 0, a.max = Math.max(a.max, t.maxEle || 0), a), { n: 0, d: 0, g: 0, s: 0, max: 0 });
}
const years = () => [...new Set(TREKS.map(t => (t.date || '').slice(0, 4)).filter(Boolean))].sort().reverse();
const filtered = () => TREKS.filter(t => yearFilter === 'tutti' || (t.date || '').startsWith(yearFilter));

// ---------------------------------------------------------------- viste
const view = () => $('#view');
function setTop(html = '') { $('#topbarActions').innerHTML = html; }
function setTab(name) { $$('.tabbar a').forEach(a => a.classList.toggle('on', a.dataset.tab === name)); }
function setShell({ full = false, topbar = true } = {}) { view().classList.toggle('full', full); $('#topbar').hidden = !topbar; }

function renderDiario() {
  setShell(); setTab('diario');
  setTop(`<button class="btn sm" id="quickImport">${ICON.file}Importa</button>`);
  $('#quickImport').onclick = () => pickFiles();
  const list = filtered(); const tot = totalsFor(list); const ys = years();
  const q = query.trim().toLowerCase();
  const shown = q ? list.filter(t => [t.name, t.location, t.region, t.notes, t.companions].join(' ').toLowerCase().includes(q)) : list;
  const hasExamples = TREKS.some(t => t.example);
  const label = yearFilter === 'tutti' ? 'in totale' : `nel ${yearFilter}`;
  view().innerHTML = `
    <section class="hero">
      <h1 class="h-display hero-title">${tot.n ? `${nf0.format(Math.round(tot.g))} metri<br><em>saliti ${esc(label)}</em>` : 'Il tuo diario<br><em>di montagna</em>'}</h1>
      ${ys.length > 1 ? `<div class="year-switch" role="tablist">${['tutti', ...ys].map(y => `<button data-y="${y}" class="${y === yearFilter ? 'on' : ''}">${y === 'tutti' ? 'Tutti' : y}</button>`).join('')}</div>` : ''}
      <div class="totals">
        <div><span class="v">${tot.n}</span><span class="k">Uscite</span></div>
        <div><span class="v">${km(tot.d)}<small>km</small></span><span class="k">Distanza</span></div>
        <div><span class="v">${Math.floor(tot.s / 3600)}<small>h</small></span><span class="k">In cammino</span></div>
        <div><span class="v">${mt(tot.max)}<small>m</small></span><span class="k">Quota max</span></div>
      </div>
    </section>
    ${hasExamples ? `<div class="example-note" style="margin-top:16px"><span><b>Dati di esempio.</b> Quattro uscite finte per mostrarti l'app. Importa le tue e cancellale quando vuoi.</span><button class="btn sm" id="clearEx">Elimina esempi</button></div>` : ''}
    <section class="section">
      <div class="section-head"><h2>Uscite</h2><span class="muted" style="font-size:13px">${shown.length} ${shown.length === 1 ? 'trekking' : 'trekking'}</span></div>
      ${TREKS.length > 3 ? `<label class="search">${ICON.search}<input id="q" type="search" placeholder="Cerca per nome, luogo, compagni" value="${esc(query)}"></label>` : ''}
      <div class="list" id="list">${shown.map(trekCard).join('') || emptyState()}</div>
    </section>`;
  $$('.year-switch button').forEach(b => b.onclick = () => { yearFilter = b.dataset.y; ls.set('year', yearFilter); renderDiario(); });
  const qi = $('#q'); if (qi) qi.oninput = () => { query = qi.value; const ql = query.trim().toLowerCase(); $('#list').innerHTML = list.filter(t => [t.name, t.location, t.region, t.notes, t.companions].join(' ').toLowerCase().includes(ql)).map(trekCard).join('') || '<p class="muted">Nessun risultato.</p>'; };
  const ce = $('#clearEx'); if (ce) ce.onclick = async () => { for (const t of TREKS.filter(t => t.example)) await remove(t.id); toast('Esempi eliminati'); renderDiario(); };
}
function emptyState() {
  return `<div class="empty card">
    <svg class="art" viewBox="0 0 140 80" aria-hidden="true"><path d="M4 76 L46 22 L66 46 L88 14 L136 76 Z" fill="var(--surface-2)" stroke="var(--line)" stroke-width="2"/><rect x="80" y="52" width="22" height="7" fill="var(--accent)"/><rect x="80" y="59" width="22" height="7" fill="#fff"/><rect x="80" y="66" width="22" height="7" fill="var(--accent)"/></svg>
    <h3>Nessun trekking ${yearFilter !== 'tutti' ? 'in questo anno' : 'ancora'}</h3>
    <p class="muted" style="margin:0;max-width:34ch">Importa un file GPX da Garmin, Strava, Komoot o Apple Salute, oppure registra il prossimo giro.</p>
    <a class="btn primary" href="#nuovo">Aggiungi il primo</a></div>`;
}

// ---- dettaglio
async function renderTrek(id) {
  const t = TREKS.find(x => x.id === id) || await DB.get(id);
  if (!t) { location.hash = '#diario'; return; }
  setShell({ full: true, topbar: false }); setTab('diario');
  const hasTrack = (t.track || []).length > 1;
  const pace = t.moving && t.distance ? (t.moving / 60) / (t.distance / 1000) : 0;
  const vam = t.moving && t.gain ? t.gain / (t.moving / 3600) : 0;
  view().innerHTML = `
    <div style="position:relative">
      <a class="back-fab" href="#diario" aria-label="Indietro">${ICON.back}</a>
      ${hasTrack ? '<div class="detail-map" id="map"></div>' : '<div class="detail-map" style="display:grid;place-items:center;height:180px;min-height:0" id="nomap"><span class="muted">Nessuna traccia GPS</span></div>'}
    </div>
    <div class="detail-wrap">
      <div class="card detail-head">
        <div class="row" style="gap:8px">${diffTag(t.difficulty)}<span class="muted" style="font-size:13px">${esc(DIFF[t.difficulty]?.name || '')}</span>${t.example ? '<span class="chip example">Esempio</span>' : ''}</div>
        <h1 class="h-display">${esc(t.name || 'Trekking senza nome')}</h1>
        <div class="where"><span>${esc([t.location, t.region].filter(Boolean).join(', ') || 'Luogo non indicato')}</span><span>·</span><span>${esc(fmtDate(t.date, true))}</span></div>
        ${t.rating || t.companions ? `<div class="row" style="gap:12px">${stars(t.rating)}${t.companions ? `<span class="muted" style="font-size:13px">con ${esc(t.companions)}</span>` : ''}</div>` : ''}
      </div>
      <div class="section" style="margin-top:14px">
        <div class="stat-grid">
          <div><div class="v">${km(t.distance)}<small>km</small></div><div class="k">Distanza</div></div>
          <div><div class="v">${mt(t.gain)}<small>m</small></div><div class="k">Dislivello +</div></div>
          <div><div class="v">${fmtDur(t.moving || t.duration)}</div><div class="k">${t.moving ? 'In movimento' : 'Durata'}</div></div>
          <div><div class="v">${t.maxEle != null ? mt(t.maxEle) : '–'}<small>m</small></div><div class="k">Quota max</div></div>
          <div><div class="v">${t.loss ? mt(t.loss) : '–'}<small>m</small></div><div class="k">Dislivello −</div></div>
          <div><div class="v">${vam ? mt(vam) : (pace ? nf1.format(60 / pace) : '–')}<small>${vam ? 'm/h' : 'km/h'}</small></div><div class="k">${vam ? 'Vel. salita' : 'Velocità'}</div></div>
        </div>
      </div>
      ${hasTrack && t.track.some(p => p[2] != null) ? `
      <div class="section"><div class="section-head"><h2>Profilo</h2><span class="muted" style="font-size:12px">Colore = pendenza</span></div>
        <div class="card profile"><div class="profile-read" id="pread"><span>Scorri sul grafico</span><span></span></div><canvas id="ele"></canvas></div></div>` : ''}
      <div class="section"><div class="section-head"><h2>Foto</h2></div><div class="photos" id="photos"></div></div>
      ${t.notes ? `<div class="section"><div class="section-head"><h2>Note</h2></div><div class="card notes">${esc(t.notes)}</div></div>` : ''}
      <div class="section">
        <div class="actions">
          <button class="btn primary" id="shareBtn">${ICON.share}Condividi</button>
          <button class="btn" id="gpxBtn" ${hasTrack ? '' : 'disabled'}>${ICON.gpx}Esporta GPX</button>
          <a class="btn" href="#modifica-${t.id}">${ICON.edit}Modifica</a>
          <button class="btn danger" id="delBtn">${ICON.trash}Elimina</button>
        </div>
        <p class="muted" style="font-size:12px;margin:4px 0 0">${t.fileName ? 'Importato da ' + esc(t.fileName) + '. ' : ''}${t.startTime ? 'Partenza alle ' + new Date(t.startTime).toLocaleTimeString('it-IT', { hour: '2-digit', minute: '2-digit' }) + '. ' : ''}${t.duration && t.moving ? 'Tempo totale con soste ' + fmtDur(t.duration) + '.' : ''}</p>
      </div>
    </div>`;
  window.scrollTo(0, 0);
  let cursor = null, map = null;
  if (hasTrack) {
    map = makeMap($('#map'));
    const ll = t.track.map(p => [p[0], p[1]]);
    L.polyline(ll, { color: '#fff', weight: 8, opacity: .9 }).addTo(map);
    const line = L.polyline(ll, { color: accent(), weight: 4.5 }).addTo(map);
    L.marker(ll[0], { icon: pin('start'), title: 'Partenza' }).addTo(map);
    if (dist(t.track[0], t.track[t.track.length - 1]) > 60) L.marker(ll[ll.length - 1], { icon: pin('end'), title: 'Arrivo' }).addTo(map);
    // vetta
    let hi = 0; t.track.forEach((p, i) => { if ((p[2] ?? -1e9) > (t.track[hi][2] ?? -1e9)) hi = i; });
    if (t.track[hi][2] != null) L.marker(ll[hi], { icon: L.divIcon({ className: '', html: `<div style="position:absolute;transform:translate(-50%,-140%);width:max-content;white-space:nowrap;background:var(--ink);color:var(--bg);font:700 12px var(--font-display);padding:3px 7px;border-radius:6px">▲ ${mt(t.track[hi][2])} m</div>`, iconSize: [0, 0] }) }).addTo(map);
    map.fitBounds(line.getBounds(), { padding: [30, 30] });
    cursor = L.marker(ll[0], { icon: pin('cursor'), interactive: false, opacity: 0 }).addTo(map);
    if (t.track.some(p => p[2] != null)) drawProfile($('#ele'), t, (i) => {
      if (i == null) { cursor.setOpacity(0); return; }
      cursor.setLatLng(ll[i]).setOpacity(1);
    });
  }
  renderPhotos(t);
  $('#shareBtn').onclick = () => shareTrek(t);
  $('#gpxBtn').onclick = () => shareFile(new File([toGPX(t)], slug(t.name) + '.gpx', { type: 'application/gpx+xml' }), t.name);
  $('#delBtn').onclick = () => confirmSheet(`Eliminare “${t.name || 'questo trekking'}”?`, 'Traccia, note e foto verranno cancellate da questo dispositivo.', 'Elimina', async () => { await remove(t.id); toast('Trekking eliminato'); location.hash = '#diario'; });
}

function drawProfile(canvas, t, onHover) {
  const pts = t.track; const c = cumDist(pts); const e = smoothEle(pts, 2);
  const valid = e.map((v, i) => v == null ? null : i).filter(v => v != null);
  const css = getComputedStyle(document.documentElement);
  const col = { ink: css.getPropertyValue('--ink'), muted: css.getPropertyValue('--muted'), line: css.getPropertyValue('--line'), fill: css.getPropertyValue('--ele-fill'), T: css.getPropertyValue('--d-T'), E: css.getPropertyValue('--d-E'), EE: css.getPropertyValue('--d-EE') };
  let W, H; const P = { l: 40, r: 8, t: 10, b: 22 };
  const minE = Math.min(...valid.map(i => e[i])), maxE = Math.max(...valid.map(i => e[i]));
  const lo = Math.floor((minE - 20) / 100) * 100, hi = Math.ceil((maxE + 20) / 100) * 100; const D = c[c.length - 1];
  const X = (d) => P.l + (d / D) * (W - P.l - P.r), Y = (v) => P.t + (1 - (v - lo) / (hi - lo)) * (H - P.t - P.b);
  // pendenza su finestra di ~100 m
  const grade = pts.map((_, i) => { let j = i; while (j < pts.length - 1 && c[j] - c[i] < 100) j++; let k = i; while (k > 0 && c[i] - c[k] < 50) k--; const dd = c[j] - c[k]; return dd > 10 && e[j] != null && e[k] != null ? (e[j] - e[k]) / dd : 0; });
  let hover = null;
  function draw() {
    const dpr = window.devicePixelRatio || 1; W = canvas.clientWidth; H = canvas.clientHeight;
    canvas.width = W * dpr; canvas.height = H * dpr; const g = canvas.getContext('2d'); g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, W, H); g.font = '600 11px Manrope, system-ui, sans-serif'; g.fillStyle = col.muted; g.strokeStyle = col.line; g.lineWidth = 1;
    const stepE = (hi - lo) > 800 ? 400 : (hi - lo) > 400 ? 200 : 100;
    for (let v = lo; v <= hi; v += stepE) { const y = Y(v); g.beginPath(); g.moveTo(P.l, y + .5); g.lineTo(W - P.r, y + .5); g.stroke(); g.textAlign = 'right'; g.textBaseline = 'middle'; g.fillText(nf0.format(v), P.l - 6, y); }
    const kmStep = D > 20000 ? 5000 : D > 8000 ? 2000 : D > 3000 ? 1000 : 500;
    g.textAlign = 'center'; g.textBaseline = 'top';
    for (let d = 0; d <= D + 1; d += kmStep) g.fillText(d === 0 ? '0' : (kmStep < 1000 ? nf1.format(d / 1000) : nf0.format(d / 1000)) + (d + kmStep > D ? ' km' : ''), Math.min(X(d), W - P.r - 14), H - P.b + 6);
    // area
    g.beginPath(); g.moveTo(X(c[valid[0]]), Y(lo)); valid.forEach(i => g.lineTo(X(c[i]), Y(e[i]))); g.lineTo(X(c[valid[valid.length - 1]]), Y(lo)); g.closePath(); g.fillStyle = col.fill; g.fill();
    // linea colorata per pendenza
    g.lineWidth = 2.4; g.lineJoin = 'round'; g.lineCap = 'round';
    for (let k = 1; k < valid.length; k++) {
      const a = valid[k - 1], b = valid[k]; const gr = Math.abs(grade[b]);
      g.strokeStyle = gr < .1 ? col.T : gr < .2 ? col.E : col.EE;
      g.beginPath(); g.moveTo(X(c[a]), Y(e[a])); g.lineTo(X(c[b]), Y(e[b])); g.stroke();
    }
    if (hover != null) {
      const x = X(c[hover]), y = Y(e[hover] ?? lo);
      g.strokeStyle = col.ink; g.lineWidth = 1; g.setLineDash([3, 3]); g.beginPath(); g.moveTo(x, P.t); g.lineTo(x, H - P.b); g.stroke(); g.setLineDash([]);
      g.fillStyle = col.ink; g.beginPath(); g.arc(x, y, 4.5, 0, Math.PI * 2); g.fill();
    }
  }
  function at(ev) {
    const r = canvas.getBoundingClientRect(); const x = Math.max(P.l, Math.min(ev.clientX - r.left, W - P.r));
    const d = ((x - P.l) / (W - P.l - P.r)) * D; let lo2 = 0, hi2 = c.length - 1;
    while (hi2 - lo2 > 1) { const m = (lo2 + hi2) >> 1; if (c[m] < d) lo2 = m; else hi2 = m; }
    return hi2;
  }
  const read = $('#pread');
  const show = (i) => {
    hover = i; draw(); onHover(i);
    if (i == null) { read.innerHTML = '<span>Scorri sul grafico</span><span></span>'; return; }
    read.innerHTML = `<span>km <b>${km(c[i])}</b> · quota <b>${e[i] != null ? mt(e[i]) : '–'} m</b></span><span>pendenza <b>${Math.round(grade[i] * 100)}%</b></span>`;
  };
  canvas.addEventListener('pointermove', ev => show(at(ev)));
  canvas.addEventListener('pointerdown', ev => show(at(ev)));
  canvas.addEventListener('pointerleave', () => show(null));
  new ResizeObserver(draw).observe(canvas); draw();
}

async function renderPhotos(t) {
  const box = $('#photos'); if (!box) return;
  const photos = await DB.photos(t.id);
  box.innerHTML = photos.map(p => `<button data-id="${p.id}" aria-label="Apri foto"><img alt="" src="${URL.createObjectURL(p.thumb || p.blob)}"></button>`).join('') + `<button class="add-photo" id="addPhoto">+ Aggiungi foto</button>`;
  $('#addPhoto').onclick = () => { const inp = $('#photoInput'); inp.value = ''; inp.onchange = async () => { await addPhotos(t, [...inp.files], photos.length); renderPhotos(t); }; inp.click(); };
  $$('button[data-id]', box).forEach(b => b.onclick = () => { const p = photos.find(x => x.id === b.dataset.id); lightbox(t, p); });
}
async function resizeImage(file, max, q = .82) {
  const bmp = await createImageBitmap(file).catch(() => null);
  let w, h, src;
  if (bmp) { w = bmp.width; h = bmp.height; src = bmp; } else { src = await new Promise((res, rej) => { const i = new Image(); i.onload = () => res(i); i.onerror = rej; i.src = URL.createObjectURL(file); }); w = src.naturalWidth; h = src.naturalHeight; }
  const s = Math.min(1, max / Math.max(w, h)); const cv = document.createElement('canvas'); cv.width = Math.round(w * s); cv.height = Math.round(h * s);
  cv.getContext('2d').drawImage(src, 0, 0, cv.width, cv.height);
  return new Promise(res => cv.toBlob(res, 'image/jpeg', q));
}
async function addPhotos(t, files, start) {
  toast('Salvo le foto…');
  let i = start;
  for (const f of files) {
    try { const blob = await resizeImage(f, 1800); const thumb = await resizeImage(f, 420, .75); await DB.putPhoto({ id: uid(), trekId: t.id, blob, thumb, order: i++, name: f.name }); } catch { toast('Una foto non è leggibile'); }
  }
  toast('Foto aggiunte');
}
function lightbox(t, p) {
  const el = document.createElement('div'); el.className = 'lightbox';
  el.innerHTML = `<img alt="" src="${URL.createObjectURL(p.blob)}"><div class="row"><button class="btn sm" data-a="share">${ICON.share}Condividi</button><button class="btn sm danger" data-a="del">${ICON.trash}Elimina</button><button class="btn sm" data-a="close">Chiudi</button></div>`;
  el.onclick = async (e) => {
    const a = e.target.closest('[data-a]')?.dataset.a;
    if (a === 'del') { await DB.delPhoto(p.id); el.remove(); renderPhotos(t); toast('Foto eliminata'); }
    else if (a === 'share') shareFile(new File([p.blob], p.name || 'foto.jpg', { type: 'image/jpeg' }), t.name);
    else if (a === 'close' || e.target === el) el.remove();
  };
  document.body.appendChild(el);
}

// ---- condivisione
async function shareFile(file, title) {
  try {
    if (navigator.canShare && navigator.canShare({ files: [file] })) { await navigator.share({ files: [file], title }); return; }
  } catch (e) { if (e && e.name === 'AbortError') return; }
  const a = document.createElement('a'); a.href = URL.createObjectURL(file); a.download = file.name; document.body.appendChild(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 4000); toast('File scaricato');
}
async function shareCard(t) {
  await document.fonts?.ready;
  const W = 1080, H = 1350; const cv = document.createElement('canvas'); cv.width = W; cv.height = H; const g = cv.getContext('2d');
  const ink = '#121714', red = '#E0262E', paper = '#F2F3EE';
  g.fillStyle = ink; g.fillRect(0, 0, W, H);
  // curve di livello decorative
  g.strokeStyle = 'rgba(255,255,255,.06)'; g.lineWidth = 2;
  for (let r = 60; r < 1500; r += 46) { g.beginPath(); g.ellipse(780, 360, r * 1.15, r * .8, -.4, 0, Math.PI * 2); g.stroke(); }
  const pts = t.track || [];
  if (pts.length > 1) {
    const xy = project(pts, W, 760, 110).map(p => [p[0], p[1] + 70]);
    g.lineJoin = 'round'; g.lineCap = 'round';
    g.strokeStyle = 'rgba(255,255,255,.95)'; g.lineWidth = 20; g.beginPath(); xy.forEach((p, i) => i ? g.lineTo(p[0], p[1]) : g.moveTo(p[0], p[1])); g.stroke();
    g.strokeStyle = red; g.lineWidth = 10; g.stroke();
    g.fillStyle = '#1E9E5A'; g.strokeStyle = '#fff'; g.lineWidth = 6; g.beginPath(); g.arc(xy[0][0], xy[0][1], 16, 0, Math.PI * 2); g.fill(); g.stroke();
    // profilo
    if (pts.some(p => p[2] != null)) {
      const c = cumDist(pts), D = c[c.length - 1]; const e = pts.map(p => p[2]); const v = e.filter(x => x != null); const mn = Math.min(...v), mx = Math.max(...v);
      const top = 860, bot = 960; g.beginPath(); g.moveTo(80, bot);
      pts.forEach((p, i) => { if (p[2] != null) g.lineTo(80 + (c[i] / D) * (W - 160), bot - ((p[2] - mn) / Math.max(1, mx - mn)) * (bot - top)); });
      g.lineTo(W - 80, bot); g.closePath(); g.fillStyle = 'rgba(224,38,46,.28)'; g.fill();
    }
  }
  // segnavia
  [[red], ['#fff'], [red]].forEach((cl, i) => { g.fillStyle = cl[0]; g.fillRect(80, 80 + i * 18, 64, 18); });
  g.fillStyle = paper; g.font = '700 34px "Barlow Condensed", sans-serif'; g.textBaseline = 'top'; g.fillText('SEGNAVIA', 160, 86);
  g.font = '600 30px Manrope, sans-serif'; g.fillStyle = 'rgba(242,243,238,.7)'; g.textAlign = 'right'; g.fillText(fmtDate(t.date), W - 80, 90); g.textAlign = 'left';
  // titolo
  let fs = 92; g.font = `700 ${fs}px "Barlow Condensed", sans-serif`; const title = (t.name || 'Trekking').toUpperCase();
  while (g.measureText(title).width > W - 160 && fs > 54) { fs -= 4; g.font = `700 ${fs}px "Barlow Condensed", sans-serif`; }
  const words = title.split(' '); const lines = []; let cur = '';
  for (const w of words) { const tt = cur ? cur + ' ' + w : w; if (g.measureText(tt).width > W - 160 && cur) { lines.push(cur); cur = w; } else cur = tt; } lines.push(cur);
  const ty = 1000; g.fillStyle = paper; lines.slice(0, 2).forEach((l, i) => g.fillText(l, 80, ty + i * fs * .95 - (lines.length > 1 ? fs * .9 : 0)));
  g.font = '600 30px Manrope, sans-serif'; g.fillStyle = 'rgba(242,243,238,.7)'; g.fillText([t.location, t.region].filter(Boolean).join(', '), 80, ty + fs + 4);
  // numeri
  const stats = [[km(t.distance), 'KM'], [mt(t.gain), 'M D+'], [fmtDur(t.moving || t.duration).replace(' ', ''), 'TEMPO'], [t.maxEle ? mt(t.maxEle) : '–', 'M QUOTA MAX']];
  const sy = 1180, cw = (W - 160) / 4;
  stats.forEach(([v, k], i) => { const x = 80 + i * cw; g.fillStyle = paper; g.font = '700 70px "Barlow Condensed", sans-serif'; g.fillText(v, x, sy); g.font = '700 22px Manrope, sans-serif'; g.fillStyle = red; g.fillText(k, x, sy + 76); });
  return new Promise(res => cv.toBlob(res, 'image/png'));
}
async function shareTrek(t) {
  openSheet(`<h3>Condividi</h3>
    <p class="muted" style="margin:0">Scegli cosa mandare. Su iPhone si apre il menu di condivisione per WhatsApp, Instagram, Messaggi.</p>
    <div style="border-radius:14px;overflow:hidden;background:#121714;width:192px;height:240px;margin:0 auto;flex:none"><img id="cardPrev" alt="Anteprima della card" style="width:192px;height:240px;display:block"></div>
    <div class="choices">
      <button class="card choice" data-s="card"><span class="ic">${ICON.share}</span><span><b>Card con mappa e numeri</b><span class="d">Immagine pronta per storie e chat</span></span>${ICON.chev}</button>
      <button class="card choice" data-s="gpx" ${(t.track || []).length > 1 ? '' : 'disabled'}><span class="ic">${ICON.gpx}</span><span><b>Traccia GPX</b><span class="d">Per chi vuole rifare il giro con Komoot, Garmin, Strava</span></span>${ICON.chev}</button>
      <button class="card choice" data-s="text"><span class="ic">${ICON.file}</span><span><b>Testo riassuntivo</b><span class="d">Copia nome, luogo e numeri</span></span>${ICON.chev}</button>
    </div>`);
  const blob = await shareCard(t); const prev = $('#cardPrev'); if (prev) prev.src = URL.createObjectURL(blob);
  $('#sheetBody').onclick = async (e) => {
    const s = e.target.closest('[data-s]')?.dataset.s; if (!s) return;
    if (s === 'card') await shareFile(new File([blob], slug(t.name) + '.png', { type: 'image/png' }), t.name);
    if (s === 'gpx') await shareFile(new File([toGPX(t)], slug(t.name) + '.gpx', { type: 'application/gpx+xml' }), t.name);
    if (s === 'text') {
      const txt = `⛰️ ${t.name}\n📍 ${[t.location, t.region].filter(Boolean).join(', ')} · ${fmtDate(t.date)}\n${km(t.distance)} km · ↑${mt(t.gain)} m · ${fmtDur(t.moving || t.duration)}${t.maxEle ? ' · quota max ' + mt(t.maxEle) + ' m' : ''}\nDifficoltà ${t.difficulty}`;
      try { if (navigator.share) { await navigator.share({ text: txt, title: t.name }); } else { await navigator.clipboard.writeText(txt); toast('Testo copiato'); } } catch (err) { if (err?.name !== 'AbortError') { try { await navigator.clipboard.writeText(txt); toast('Testo copiato'); } catch { toast('Copia non riuscita'); } } }
    }
    closeSheet();
  };
}

// ---- sheet
function openSheet(html) { $('#sheetBody').innerHTML = html; $('#sheet').hidden = false; $('#sheetBody').onclick = null; }
function closeSheet() { $('#sheet').hidden = true; $('#sheetBody').innerHTML = ''; }
$('#sheet').addEventListener('click', e => { if (e.target.id === 'sheet') closeSheet(); });
function confirmSheet(title, text, cta, fn) {
  openSheet(`<h3>${esc(title)}</h3><p class="muted" style="margin:0">${esc(text)}</p><div class="actions"><button class="btn" data-c="0">Annulla</button><button class="btn primary" data-c="1">${esc(cta)}</button></div>`);
  $('#sheetBody').onclick = async (e) => { const c = e.target.closest('[data-c]')?.dataset.c; if (c == null) return; closeSheet(); if (c === '1') await fn(); };
}

// ---- nuovo
function renderNuovo() {
  setShell(); setTab('nuovo'); setTop('');
  view().innerHTML = `
    <section class="hero"><h1 class="h-display hero-title">Nuovo<br><em>trekking</em></h1></section>
    <div class="choices section">
      <button class="card choice" id="cImport"><span class="ic">${ICON.file}</span><span><b>Importa traccia GPX o TCX</b><span class="d">Da Garmin Connect, Strava, Komoot, Suunto, Wikiloc. Anche più file insieme.</span></span>${ICON.chev}</button>
      <button class="card choice" id="cApple"><span class="ic">${ICON.heart}</span><span><b>Importa da Apple Salute</b><span class="d">Carica il file esportazione.zip: scegli tu quali percorsi tenere.</span></span>${ICON.chev}</button>
      <a class="card choice" href="#registra"><span class="ic">${ICON.rec}</span><span><b>Registra adesso con il GPS</b><span class="d">Tieni l'app aperta durante il giro.</span></span>${ICON.chev}</a>
      <a class="card choice" href="#manuale"><span class="ic">${ICON.pen}</span><span><b>Inserisci a mano</b><span class="d">Senza traccia: nome, luogo, km e dislivello.</span></span>${ICON.chev}</a>
    </div>
    <p class="muted" style="font-size:13px;margin-top:16px">Non sai dove trovare il GPX? Guarda le istruzioni in <a href="#altro">Altro → Collega le tue app</a>.</p>`;
  $('#cImport').onclick = () => pickFiles();
  $('#cApple').onclick = () => pickFiles();
}
function pickFiles() { const i = $('#fileInput'); i.value = ''; i.click(); }
$('#fileInput').addEventListener('change', async (e) => { const files = [...e.target.files]; if (files.length) await handleFiles(files); });

async function handleFiles(files) {
  const drafts = []; const errors = [];
  toast(files.length > 1 ? `Leggo ${files.length} file…` : 'Leggo il file…', 8000);
  for (const f of files) {
    try {
      if (/\.zip$/i.test(f.name) || f.type.includes('zip')) { drafts.push(...await readZip(f)); continue; }
      const parsed = parseTrackFile(f.name, await f.text()); drafts.push(buildDraft(parsed, f.name, 'gpx'));
    } catch (err) { errors.push(err.message || f.name); }
  }
  $('#toast').hidden = true;
  if (!drafts.length) { toast(errors[0] || 'Nessuna traccia trovata nel file'); return; }
  const dupes = (d) => TREKS.some(t => t.startTime && d.startTime && Math.abs(t.startTime - d.startTime) < 60000);
  if (drafts.length === 1) { pendingDraft = drafts[0]; if (dupes(pendingDraft)) toast('Attenzione: sembra già nel diario'); location.hash = '#importa'; return; }
  drafts.sort((a, b) => (b.startTime || 0) - (a.startTime || 0));
  openSheet(`<h3>${drafts.length} percorsi trovati</h3>
    <p class="muted" style="margin:0">Sono preselezionati quelli che sembrano trekking (dislivello oltre 200 m e passo da camminata). Quelli già nel diario sono esclusi.</p>
    <div class="sel-list">${drafts.map((d, i) => { const sp = d.moving ? (d.distance / d.moving) * 3.6 : 3; const like = d.gain >= 200 && sp < 6.5 && !dupes(d); return `<label class="sel-item"><input type="checkbox" data-i="${i}" ${like ? 'checked' : ''}><span style="min-width:0"><b style="font-size:14px">${esc(d.name || fmtDate(d.date, true))}</b><br><span class="muted" style="font-size:12px">${km(d.distance)} km · ↑${mt(d.gain)} m · ${fmtDur(d.moving || d.duration)}${dupes(d) ? ' · già presente' : ''}</span></span><span class="muted" style="font-size:12px">${esc(fmtDate(d.date))}</span></label>`; }).join('')}</div>
    <div class="actions"><button class="btn" data-a="none">Deseleziona</button><button class="btn primary" data-a="ok">Importa selezionati</button></div>`);
  $('#sheetBody').onclick = async (e) => {
    const a = e.target.closest('[data-a]')?.dataset.a; if (!a) return;
    if (a === 'none') { $$('.sel-list input').forEach(i => (i.checked = false)); return; }
    const chosen = $$('.sel-list input').filter(i => i.checked).map(i => drafts[+i.dataset.i]);
    closeSheet(); if (!chosen.length) return;
    toast(`Importo ${chosen.length} trekking…`, 10000);
    for (const d of chosen) {
      const g = await reverseGeocode(d.track[0][0], d.track[0][1]); if (g) { d.location = g.location; d.region = g.region; }
      if (!d.name) d.name = d.location ? `Giro da ${d.location}` : `Trekking del ${fmtDate(d.date)}`;
      await save(d); await new Promise(r => setTimeout(r, 1100)); // limite Nominatim 1 richiesta/s
    }
    toast(`${chosen.length} trekking importati`); location.hash = '#diario'; renderRoute();
  };
}
async function readZip(file) {
  if (!window.JSZip) throw new Error('Lettura zip non disponibile');
  const zip = await JSZip.loadAsync(file); const out = [];
  const entries = Object.values(zip.files).filter(z => !z.dir && /\.(gpx|tcx)$/i.test(z.name) && !z.name.includes('__MACOSX'));
  if (!entries.length) throw new Error(`${file.name}: nessun GPX dentro lo zip. Per Apple Salute serve il file esportazione.zip con la cartella workout-routes.`);
  for (const z of entries) {
    try { const parsed = parseTrackFile(z.name, await z.async('string')); out.push(buildDraft(parsed, z.name.split('/').pop(), /workout-routes/.test(z.name) ? 'apple' : 'gpx')); } catch {}
  }
  return out;
}

// ---- form (importa / manuale / modifica)
function renderForm(mode, id) {
  setShell(); setTab('nuovo'); setTop('');
  let t;
  if (mode === 'edit') { t = TREKS.find(x => x.id === id); if (!t) { location.hash = '#diario'; return; } t = structuredClone(t); }
  else if (mode === 'import') { t = pendingDraft; if (!t) { location.hash = '#nuovo'; return; } }
  else t = { id: uid(), name: '', location: '', region: '', date: todayISO(), difficulty: 'E', rating: 0, notes: '', companions: '', track: [], distance: 0, gain: 0, loss: 0, duration: 0, moving: 0, maxEle: null, source: 'manual', createdAt: Date.now() };
  const hasTrack = (t.track || []).length > 1; const durSec = t.moving || t.duration || 0;
  view().innerHTML = `
    <section class="hero"><h1 class="h-display hero-title" style="font-size:clamp(34px,9vw,52px)">${mode === 'edit' ? 'Modifica' : mode === 'import' ? 'Quasi fatto' : 'A mano'}</h1></section>
    ${hasTrack ? `<div class="card import-preview section" style="margin-top:14px"><div class="thumb">${thumbSVG(t)}</div><div><b>${km(t.distance)} km · ↑${mt(t.gain)} m</b><div class="muted" style="font-size:13px">${t.track.length} punti GPS${t.fileName ? ' da ' + esc(t.fileName) : ''}${t.maxEle ? ' · quota max ' + mt(t.maxEle) + ' m' : ''}</div></div></div>` : ''}
    <form class="form section" id="f" novalidate>
      <div class="field"><label for="f-name">Nome del giro</label><input id="f-name" required placeholder="Es. Anello del Lago di Braies" value="${esc(t.name)}"></div>
      <div class="two">
        <div class="field"><label for="f-loc">Località</label><input id="f-loc" placeholder="${hasTrack ? 'Cerco in automatico…' : 'Es. Braies'}" value="${esc(t.location)}"></div>
        <div class="field"><label for="f-reg">Zona o regione</label><input id="f-reg" placeholder="Es. Dolomiti" value="${esc(t.region)}"></div>
      </div>
      <div class="field"><label for="f-date">Data</label><input id="f-date" type="date" value="${esc(t.date)}"></div>
      <div class="field"><span class="lab">Difficoltà (scala CAI)</span>
        <div class="diff-pick" id="f-diff">${Object.keys(DIFF).map(k => `<button type="button" data-d="${k}" style="--dc:var(--d-${k})" class="${t.difficulty === k ? 'on' : ''}"><b>${k}</b><span>${DIFF[k].short}</span></button>`).join('')}</div></div>
      <div class="field"><span class="lab">Voto</span><div class="rate-pick" id="f-rate">${[1, 2, 3, 4, 5].map(n => `<button type="button" data-r="${n}" class="${n <= t.rating ? 'on' : ''}" aria-label="${n} stelle">★</button>`).join('')}</div></div>
      <div class="three">
        <div class="field"><label for="f-km">Km</label><input id="f-km" inputmode="decimal" value="${t.distance ? nf1.format(t.distance / 1000) : ''}" ${hasTrack ? 'readonly' : ''}></div>
        <div class="field"><label for="f-gain">D+ metri</label><input id="f-gain" inputmode="numeric" value="${t.gain || ''}" ${hasTrack ? 'readonly' : ''}></div>
        <div class="field"><label for="f-max">Quota max</label><input id="f-max" inputmode="numeric" value="${t.maxEle ?? ''}" ${hasTrack ? 'readonly' : ''}></div>
      </div>
      <div class="two">
        <div class="field"><label for="f-h">Ore di cammino</label><input id="f-h" inputmode="numeric" value="${durSec ? Math.floor(durSec / 3600) : ''}"></div>
        <div class="field"><label for="f-m">Minuti</label><input id="f-m" inputmode="numeric" value="${durSec ? Math.round((durSec % 3600) / 60) : ''}"></div>
      </div>
      <div class="field"><label for="f-comp">Con chi</label><input id="f-comp" placeholder="Es. Giulia, Marco" value="${esc(t.companions)}"></div>
      <div class="field"><label for="f-notes">Note</label><textarea id="f-notes" placeholder="Sentiero, rifugio, condizioni, cosa ricordare">${esc(t.notes)}</textarea></div>
      <div class="actions"><a class="btn" href="${mode === 'edit' ? '#trek-' + t.id : '#nuovo'}">Annulla</a><button class="btn primary" type="submit">Salva</button></div>
    </form>`;
  $$('#f-diff button').forEach(b => b.onclick = () => { t.difficulty = b.dataset.d; $$('#f-diff button').forEach(x => x.classList.toggle('on', x === b)); });
  $$('#f-rate button').forEach(b => b.onclick = () => { const n = +b.dataset.r; t.rating = t.rating === n ? 0 : n; $$('#f-rate button').forEach(x => x.classList.toggle('on', +x.dataset.r <= t.rating)); });
  if (hasTrack && !t.location && mode === 'import') reverseGeocode(t.track[0][0], t.track[0][1]).then(g => {
    if (!g) { $('#f-loc').placeholder = 'Es. Braies'; return; }
    if (!$('#f-loc').value) $('#f-loc').value = g.location; if (!$('#f-reg').value) $('#f-reg').value = g.region;
    if (!$('#f-name').value && g.location) $('#f-name').placeholder = `Es. Giro da ${g.location}`;
  });
  $('#f').onsubmit = async (e) => {
    e.preventDefault();
    const num = (v) => parseFloat(String(v).replace(/\./g, '').replace(',', '.'));
    t.name = $('#f-name').value.trim() || $('#f-name').placeholder.replace(/^Es\. /, '') || 'Trekking';
    t.location = $('#f-loc').value.trim(); t.region = $('#f-reg').value.trim(); t.date = $('#f-date').value || todayISO();
    t.companions = $('#f-comp').value.trim(); t.notes = $('#f-notes').value.trim();
    if (!hasTrack) { const k = parseFloat(String($('#f-km').value).replace(',', '.')); t.distance = isFinite(k) ? Math.round(k * 1000) : 0; t.gain = Math.round(num($('#f-gain').value)) || 0; const mx = num($('#f-max').value); t.maxEle = isFinite(mx) ? Math.round(mx) : null; }
    const h = parseInt($('#f-h').value) || 0, m = parseInt($('#f-m').value) || 0; const sec = h * 3600 + m * 60;
    if (sec && Math.abs(sec - (t.moving || t.duration || 0)) > 59) { t.moving = sec; if (!t.duration || t.duration < sec) t.duration = sec; }
    delete t.example;
    await save(t); pendingDraft = null; ls.del('rec');
    toast('Salvato'); location.hash = '#trek-' + t.id;
  };
}

// ---- mappa globale
function renderMappa() {
  setShell({ full: true, topbar: false }); setTab('mappa');
  view().innerHTML = `<div class="map-full" id="gmap"></div><div class="card map-legend" id="legend" hidden></div>`;
  const map = makeMap($('#gmap'), { zoomSnap: .5 });
  const list = TREKS.filter(t => (t.track || []).length > 1);
  if (!list.length) { map.setView([46.3, 10.6], 7); $('#legend').hidden = false; $('#legend').innerHTML = `<span class="muted">Le tracce dei tuoi trekking appariranno qui.</span><a class="btn sm primary" href="#nuovo">Aggiungi</a>`; return; }
  const group = L.featureGroup().addTo(map); const col = accent();
  list.forEach(t => {
    const ll = t.track.map(p => [p[0], p[1]]);
    const casing = L.polyline(ll, { color: '#fff', weight: 7, opacity: .85 }).addTo(group);
    const line = L.polyline(ll, { color: col, weight: 4 }).addTo(group);
    const sel = () => {
      group.eachLayer(l => l.setStyle && l.options.color !== '#fff' && l.setStyle({ weight: 4, opacity: .55 })); line.setStyle({ weight: 6, opacity: 1 }); line.bringToFront();
      const lg = $('#legend'); lg.hidden = false;
      lg.innerHTML = `<a href="#trek-${t.id}" style="min-width:0"><div class="t-name">${esc(t.name)}</div><div class="muted" style="font-size:13px">${esc(fmtDate(t.date))} · ${km(t.distance)} km · ↑${mt(t.gain)} m</div></a><a class="btn sm primary" href="#trek-${t.id}">Apri</a>`;
    };
    line.on('click', sel); casing.on('click', sel);
    L.marker(ll[0], { icon: pin('start'), title: t.name }).on('click', sel).addTo(group);
  });
  map.fitBounds(group.getBounds(), { padding: [40, 40], maxZoom: 13 });
  const locBtn = L.control({ position: 'bottomright' });
  locBtn.onAdd = () => { const d = L.DomUtil.create('div', 'leaflet-bar'); d.innerHTML = `<a href="#" role="button" title="Dove sono" style="display:grid;place-items:center">${ICON.locate.replace('<svg', '<svg width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"')}</a>`; L.DomEvent.on(d, 'click', (e) => { L.DomEvent.stop(e); map.locate({ setView: true, maxZoom: 14 }); }); return d; };
  locBtn.addTo(map);
  map.on('locationfound', e => L.marker(e.latlng, { icon: pin('me') }).addTo(map));
  map.on('locationerror', () => toast('Posizione non disponibile'));
}

// ---- statistiche
function renderStats() {
  setShell(); setTab('statistiche'); setTop('');
  const list = filtered(); const ys = years(); const tot = totalsFor(list);
  const metric = ls.get('metric', 'gain');
  const mLabel = { gain: 'Dislivello (m)', distance: 'Distanza (km)', n: 'Uscite' }[metric];
  // per mese (anno selezionato) oppure per anno (tutti)
  let buckets;
  if (yearFilter === 'tutti' && ys.length > 1) buckets = ys.slice().reverse().map(y => ({ k: y, items: TREKS.filter(t => t.date?.startsWith(y)) }));
  else { const y = yearFilter === 'tutti' ? (ys[0] || String(new Date().getFullYear())) : yearFilter; buckets = MONTHS.map((m, i) => ({ k: m, items: TREKS.filter(t => t.date?.startsWith(`${y}-${String(i + 1).padStart(2, '0')}`)) })); }
  const val = (items) => metric === 'n' ? items.length : metric === 'distance' ? items.reduce((a, t) => a + (t.distance || 0), 0) / 1000 : items.reduce((a, t) => a + (t.gain || 0), 0);
  const vals = buckets.map(b => val(b.items)); const mx = Math.max(1, ...vals);
  const niceMax = (() => { const p = Math.pow(10, Math.floor(Math.log10(mx))); const n = [1, 2, 2.5, 5, 10].find(f => f * p >= mx) * p; return n; })();
  const W = Math.max(300, Math.min(728, (view().clientWidth || 360) - 64)), H = 220, PL = 44, PB = 26, PT = 18; const bw = (W - PL) / buckets.length;
  const ticks = [0, .25, .5, .75, 1].map(f => f * niceMax);
  const fmtV = (v) => metric === 'distance' ? (v >= 100 ? nf0.format(v) : nf1.format(v)) : nf0.format(v);
  const bars = buckets.map((b, i) => { const v = vals[i]; const h = (v / niceMax) * (H - PB - PT); const x = PL + i * bw + bw * .18; const w = bw * .64;
    return `<rect class="bar ${v ? '' : 'dim'}" x="${x.toFixed(1)}" y="${(H - PB - Math.max(h, v ? 2 : 0)).toFixed(1)}" width="${w.toFixed(1)}" height="${Math.max(h, v ? 2 : 0).toFixed(1)}" rx="3"><title>${b.k}: ${fmtV(v)}</title></rect>${v ? `<text class="lbl" x="${(x + w / 2).toFixed(1)}" y="${(H - PB - h - 5).toFixed(1)}" text-anchor="middle">${fmtV(v)}</text>` : ''}<text class="axis" x="${(x + w / 2).toFixed(1)}" y="${H - 8}" text-anchor="middle">${b.k}</text>`; }).join('');
  const grid = ticks.map(v => { const y = H - PB - (v / niceMax) * (H - PB - PT); return `<line class="grid" x1="${PL}" x2="${W}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}"/><text class="axis" x="${PL - 8}" y="${(y + 4).toFixed(1)}" text-anchor="end">${fmtV(v)}</text>`; }).join('');
  const best = (f) => list.filter(t => f(t) > 0).sort((a, b) => f(b) - f(a))[0];
  const rec = [
    ['Più dislivello', best(t => t.gain), t => `${mt(t.gain)}<small> m</small>`],
    ['Più lungo', best(t => t.distance), t => `${km(t.distance)}<small> km</small>`],
    ['Più in alto', best(t => t.maxEle || 0), t => `${mt(t.maxEle)}<small> m</small>`],
    ['Più ore in cammino', best(t => t.moving || t.duration), t => `${fmtDur(t.moving || t.duration)}`],
  ];
  const diffCount = Object.keys(DIFF).map(k => [k, list.filter(t => t.difficulty === k).length]); const dmax = Math.max(1, ...diffCount.map(d => d[1]));
  const everest = tot.g / 8849;
  view().innerHTML = `
    <section class="hero"><h1 class="h-display hero-title">I tuoi<br><em>numeri</em></h1>
      ${ys.length > 1 ? `<div class="year-switch">${['tutti', ...ys].map(y => `<button data-y="${y}" class="${y === yearFilter ? 'on' : ''}">${y === 'tutti' ? 'Tutti' : y}</button>`).join('')}</div>` : ''}
      <div class="totals">
        <div><span class="v">${tot.n}</span><span class="k">Uscite</span></div>
        <div><span class="v">${mt(tot.g)}<small>m</small></span><span class="k">D+ totale</span></div>
        <div><span class="v">${km(tot.d)}<small>km</small></span><span class="k">Distanza</span></div>
        <div><span class="v">${nf1.format(everest)}<small>×</small></span><span class="k">Everest saliti</span></div>
      </div></section>
    <section class="section"><div class="section-head"><h2>${yearFilter === 'tutti' && ys.length > 1 ? 'Per anno' : 'Per mese'}</h2>
      <div class="seg" id="metric">${[['gain', 'D+'], ['distance', 'Km'], ['n', 'Uscite']].map(([k, l]) => `<button data-m="${k}" class="${metric === k ? 'on' : ''}">${l}</button>`).join('')}</div></div>
      <div class="card chart-card"><span class="eyebrow">${mLabel}</span><svg viewBox="0 0 ${W} ${H}" role="img" aria-label="${mLabel}">${grid}${bars}</svg></div></section>
    <section class="section"><div class="section-head"><h2>Record</h2></div>
      <div class="records">${rec.map(([k, t, f]) => t ? `<a class="card record" href="#trek-${t.id}"><span class="eyebrow">${k}</span><span class="v">${f(t)}</span><span class="n">${esc(t.name)}</span></a>` : '').join('') || '<p class="muted">Ancora nessun dato.</p>'}</div></section>
    <section class="section"><div class="section-head"><h2>Difficoltà</h2></div>
      <div class="card chart-card diff-bars">${diffCount.map(([k, n]) => `<div class="diff-bar" style="--dc:var(--d-${k})"><span class="diff" data-d="${k}">${k}</span><span class="track"><i style="width:${(n / dmax) * 100}%"></i></span><b class="num" style="font-size:18px;text-align:right">${n}</b></div>`).join('')}</div></section>`;
  $$('.year-switch button').forEach(b => b.onclick = () => { yearFilter = b.dataset.y; ls.set('year', yearFilter); renderStats(); });
  $$('#metric button').forEach(b => b.onclick = () => { ls.set('metric', b.dataset.m); renderStats(); });
}

// ---- altro
function renderAltro() {
  setShell(); setTab('altro'); setTop('');
  const theme = ls.get('theme', 'system');
  view().innerHTML = `
    <section class="hero"><h1 class="h-display hero-title">Altro</h1></section>
    <section class="section"><div class="section-head"><h2>Collega le tue app</h2></div>
      <p class="muted" style="margin:0">Un'app web non può leggere direttamente Salute o Garmin, quindi si passa da un file GPX: due tocchi dall'app di origine, poi Importa qui.</p>
      <div class="card howto"><h3><span class="logo-dot" style="background:#007CC3"></span>Garmin Connect</h3><ol><li>Apri l'attività sul sito connect.garmin.com.</li><li>Ingranaggio in alto a destra → <b>Esporta in GPX</b>.</li><li>Qui: <b>+ → Importa traccia</b>. Puoi selezionarne tante insieme.</li></ol></div>
      <div class="card howto"><h3><span class="logo-dot" style="background:#FF2D55"></span>Apple Salute / Allenamento</h3><ol><li>App Salute → foto profilo → <b>Esporta tutti i dati sanitari</b>.</li><li>Salva <b>esportazione.zip</b> in File.</li><li>Qui: <b>+ → Importa da Apple Salute</b> e scegli lo zip. Ti propongo solo i percorsi che sembrano trekking.</li></ol><p class="muted" style="margin:0;font-size:13px">Più veloce per un solo giro: app gratuite come HealthFit o RunGap esportano il singolo allenamento in GPX.</p></div>
      <div class="card howto"><h3><span class="logo-dot" style="background:#FC5200"></span>Strava</h3><ol><li>Apri l'attività dal sito strava.com.</li><li>Menu <b>…</b> → <b>Esporta GPX</b>.</li></ol></div>
      <div class="card howto"><h3><span class="logo-dot" style="background:#6AA127"></span>Komoot, Wikiloc, Suunto, Polar</h3><ol><li>Dal tour o attività: <b>Scarica</b> o <b>Esporta</b> → formato GPX.</li></ol></div>
    </section>
    <section class="section"><div class="section-head"><h2>Aspetto</h2></div>
      <div class="seg" id="theme">${[['system', 'Automatico'], ['light', 'Chiaro'], ['dark', 'Scuro']].map(([k, l]) => `<button data-t="${k}" class="${theme === k ? 'on' : ''}">${l}</button>`).join('')}</div></section>
    <section class="section"><div class="section-head"><h2>Backup</h2></div>
      <p class="muted" style="margin:0">I trekking sono salvati solo su questo dispositivo. Fai un backup ogni tanto e conservalo in iCloud Drive o Google Drive: serve anche per spostarli su un altro telefono.</p>
      <div class="actions"><button class="btn" id="bExp">${ICON.gpx}Esporta backup</button><button class="btn" id="bImp">${ICON.file}Ripristina backup</button></div>
      ${TREKS.some(t => t.example) ? '' : '<button class="btn ghost sm" id="bEx" style="justify-self:start">Mostra di nuovo gli esempi</button>'}
    </section>
    <section class="section"><div class="section-head"><h2>Installa sul telefono</h2></div>
      <div class="card howto"><ol><li>iPhone: apri in Safari → <b>Condividi</b> → <b>Aggiungi alla schermata Home</b>.</li><li>Android: menu di Chrome → <b>Installa app</b>.</li></ol><p class="muted" style="margin:0;font-size:13px">Mappe © OpenStreetMap, OpenTopoMap, Waymarked Trails, Esri. Località da Nominatim.</p></div>
    </section>`;
  $$('#theme button').forEach(b => b.onclick = () => { ls.set('theme', b.dataset.t); applyTheme(); renderAltro(); });
  $('#bExp').onclick = exportBackup;
  $('#bImp').onclick = () => { const i = $('#backupInput'); i.value = ''; i.click(); };
  const be = $('#bEx'); if (be) be.onclick = async () => { for (const t of exampleTreks()) await save(t); toast('Esempi aggiunti'); location.hash = '#diario'; };
}
function applyTheme() { const t = ls.get('theme', 'system'); if (t === 'system') document.documentElement.removeAttribute('data-theme'); else document.documentElement.setAttribute('data-theme', t); }
const b64 = (blob) => new Promise(res => { const r = new FileReader(); r.onload = () => res(r.result); r.readAsDataURL(blob); });
async function exportBackup() {
  toast('Preparo il backup…');
  const photos = await DB.allPhotos();
  const data = { app: 'segnavia', version: 1, exportedAt: new Date().toISOString(), treks: TREKS, photos: await Promise.all(photos.map(async p => ({ id: p.id, trekId: p.trekId, order: p.order, name: p.name, blob: await b64(p.blob), thumb: p.thumb ? await b64(p.thumb) : null }))) };
  await shareFile(new File([JSON.stringify(data)], `segnavia-backup-${todayISO()}.json`, { type: 'application/json' }), 'Backup Segnavia');
}
$('#backupInput').addEventListener('change', async (e) => {
  const f = e.target.files[0]; if (!f) return;
  try {
    const data = JSON.parse(await f.text()); if (data.app !== 'segnavia') throw 0;
    for (const t of data.treks) await DB.put(t);
    for (const p of data.photos || []) await DB.putPhoto({ ...p, blob: await (await fetch(p.blob)).blob(), thumb: p.thumb ? await (await fetch(p.thumb)).blob() : null });
    await load(); toast(`Ripristinati ${data.treks.length} trekking`); location.hash = '#diario';
  } catch { toast('Questo file non è un backup di Segnavia'); }
});

// ---- registrazione GPS
let rec = null;
function renderRegistra() {
  setShell(); setTab('nuovo'); setTop('');
  const saved = ls.get('rec', null); if (!rec && saved) rec = { ...saved, watch: null };
  view().innerHTML = `
    <section class="rec">
      <div class="rec-map card" id="rmap"></div>
      <div class="rec-big" id="rTime">00:00:00</div>
      <div class="stat-grid"><div><div class="v" id="rKm">0,0<small>km</small></div><div class="k">Distanza</div></div><div><div class="v" id="rUp">0<small>m</small></div><div class="k">D+</div></div><div><div class="v" id="rEle">–<small>m</small></div><div class="k">Quota</div></div></div>
      <p class="muted" style="margin:0;font-size:13px" id="rMsg">Tieni lo schermo acceso e l'app in primo piano: su iPhone il GPS si ferma quando l'app va in background. Per giri lunghi usa l'orologio e importa il GPX dopo.</p>
      <div class="actions" id="rAct"></div>
    </section>`;
  const map = makeMap($('#rmap')); map.setView([46.3, 10.6], 7);
  const line = L.polyline([], { color: accent(), weight: 5 }).addTo(map); const me = L.marker([0, 0], { icon: pin('me'), opacity: 0 }).addTo(map);
  let timer = null, wake = null;
  const upd = () => {
    if (!rec) return; const st = computeStats(rec.pts); const el = rec.running ? Date.now() - rec.t0 + rec.acc : rec.acc;
    const s = Math.floor(el / 1000); $('#rTime').innerHTML = (rec.running ? '<span class="rec-dot"></span>' : '') + [s / 3600, (s % 3600) / 60, s % 60].map(v => String(Math.floor(v)).padStart(2, '0')).join(':');
    $('#rKm').innerHTML = `${km(st.distance)}<small>km</small>`; $('#rUp').innerHTML = `${mt(st.gain)}<small>m</small>`;
    const last = rec.pts[rec.pts.length - 1]; $('#rEle').innerHTML = `${last && last[2] != null ? mt(last[2]) : '–'}<small>m</small>`;
  };
  const buttons = () => {
    $('#rAct').innerHTML = !rec ? `<button class="btn primary" id="rStart" style="grid-column:1/-1">${ICON.rec}Inizia a registrare</button>`
      : rec.running ? `<button class="btn" id="rPause">Pausa</button><button class="btn primary" id="rStop">Termina</button>`
        : `<button class="btn" id="rResume">Riprendi</button><button class="btn primary" id="rStop">Termina e salva</button><button class="btn danger" id="rDiscard" style="grid-column:1/-1">Scarta registrazione</button>`;
    $('#rStart')?.addEventListener('click', start); $('#rPause')?.addEventListener('click', pause); $('#rResume')?.addEventListener('click', resume); $('#rStop')?.addEventListener('click', stop);
    $('#rDiscard')?.addEventListener('click', () => confirmSheet('Scartare la registrazione?', 'La traccia registrata finora andrà persa.', 'Scarta', () => { rec = null; ls.del('rec'); renderRegistra(); }));
  };
  const onPos = (p) => {
    const { latitude: la, longitude: lo, altitude: al, accuracy: acc } = p.coords; if (acc > 50) { $('#rMsg').textContent = `Segnale GPS debole (±${Math.round(acc)} m), aspetto…`; return; }
    $('#rMsg').textContent = `GPS ok, precisione ±${Math.round(acc)} m.`;
    const pt = [la, lo, al ?? null, p.timestamp]; const last = rec.pts[rec.pts.length - 1];
    me.setLatLng([la, lo]).setOpacity(1);
    if (!last || dist(last, pt) > Math.max(5, acc / 3)) { rec.pts.push(pt); line.addLatLng([la, lo]); if (rec.pts.length % 5 === 0) ls.set('rec', { ...rec, watch: undefined }); }
    if (rec.pts.length === 1) map.setView([la, lo], 15); else map.panTo([la, lo], { animate: true });
  };
  const watch = () => { if (!navigator.geolocation) { toast('GPS non disponibile su questo dispositivo'); return; } rec.watch = navigator.geolocation.watchPosition(onPos, (e) => { $('#rMsg').textContent = e.code === 1 ? 'Permesso posizione negato: abilitalo nelle impostazioni del browser.' : 'Posizione non disponibile.'; }, { enableHighAccuracy: true, maximumAge: 0, timeout: 30000 }); };
  const lock = async () => { try { wake = await navigator.wakeLock?.request('screen'); } catch {} };
  function start() { rec = { pts: [], t0: Date.now(), acc: 0, running: true, started: Date.now() }; watch(); lock(); timer = setInterval(upd, 1000); buttons(); }
  function pause() { rec.running = false; rec.acc += Date.now() - rec.t0; if (rec.watch != null) navigator.geolocation.clearWatch(rec.watch); ls.set('rec', { ...rec, watch: undefined }); try { wake?.release(); } catch {} upd(); buttons(); }
  function resume() { rec.running = true; rec.t0 = Date.now(); watch(); lock(); clearInterval(timer); timer = setInterval(upd, 1000); buttons(); }
  function stop() {
    if (rec.running) pause();
    if (rec.pts.length < 2) { toast('Traccia troppo corta per essere salvata'); return; }
    const d = buildDraft({ name: '', points: rec.pts }, '', 'recorded'); d.moving = Math.round(rec.acc / 1000) || d.moving; pendingDraft = d; rec = null; clearInterval(timer); location.hash = '#importa';
  }
  if (rec) { rec.pts.forEach(p => line.addLatLng([p[0], p[1]])); if (rec.pts.length) map.fitBounds(line.getBounds(), { padding: [20, 20] }); if (rec.running) { watch(); lock(); timer = setInterval(upd, 1000); } upd(); }
  buttons();
  renderRegistra.cleanup = () => { clearInterval(timer); if (rec?.watch != null) navigator.geolocation.clearWatch(rec.watch); if (rec) rec.watch = null; try { wake?.release(); } catch {} };
}

// ---------------------------------------------------------------- router
async function renderRoute() {
  if (renderRegistra.cleanup) { renderRegistra.cleanup(); renderRegistra.cleanup = null; }
  if (currentMap) { try { currentMap.remove(); } catch {} currentMap = null; }
  closeSheet();
  const h = (location.hash || '#diario').slice(1);
  if (h.startsWith('trek-')) return renderTrek(h.slice(5));
  if (h.startsWith('modifica-')) return renderForm('edit', h.slice(9));
  switch (h) {
    case 'mappa': return renderMappa();
    case 'nuovo': return renderNuovo();
    case 'importa': return renderForm('import');
    case 'manuale': return renderForm('manual');
    case 'registra': return renderRegistra();
    case 'statistiche': return renderStats();
    case 'altro': return renderAltro();
    default: window.scrollTo(0, 0); return renderDiario();
  }
}
window.addEventListener('hashchange', renderRoute);

// drag & drop su desktop
window.addEventListener('dragover', e => e.preventDefault());
window.addEventListener('drop', e => { e.preventDefault(); const f = [...(e.dataTransfer?.files || [])]; if (f.length) handleFiles(f); });

applyTheme();
load().then(renderRoute);
if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
})();
