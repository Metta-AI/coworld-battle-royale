const $ = (id) => document.getElementById(id);

const OVERLAY_ORDER = [
  'protected',
  'pickups',
  'spin',
  'seedRegion',
  'sightlines',
  'reachability',
];

const TEAM_COLORS = {
  red: '#b9473a',
  blue: '#3f6f9f',
  green: '#3f7855',
  yellow: '#a47b25',
};

const MARKER_COLORS = {
  grenade: '#8c552d',
  shield: '#3f6f9f',
  plasmaArc: '#1e8395',
  medKitActive: '#b9473a',
  medKitCandidate: '#74675a',
  spinningDiamond: '#b9782d',
  trench: '#80674f',
};

function cloneJson(value) {
  return JSON.parse(JSON.stringify(value));
}

function formatInteger(value) {
  return new Intl.NumberFormat('en-US', { maximumFractionDigits: 0 }).format(value);
}

function formatPoint(x, y) {
  return `(${formatInteger(x)}, ${formatInteger(y)}) px`;
}

function humanizeToken(value) {
  return String(value || '')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/^./, (letter) => letter.toUpperCase());
}

function fileSafeName(name) {
  const safe = String(name || 'ctf-map')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');
  return `${safe || 'ctf-map'}.json`;
}

class MapEditorApi {
  async requestJson(path, options = {}) {
    const response = await fetch(path, {
      headers: { 'Content-Type': 'application/json' },
      ...options,
    });

    let payload;
    try {
      payload = await response.json();
    } catch (error) {
      throw new Error(`The local service returned non-JSON data (${response.status}).`);
    }

    if (!response.ok) {
      const detail = payload && payload.error ? payload.error : response.statusText;
      throw new Error(`HTTP ${response.status}: ${detail}`);
    }
    return payload;
  }

  getPool() {
    return this.requestJson('/api/pool');
  }

  getPoolMap(index) {
    return this.requestJson(`/api/pool/${index}`);
  }

  generate(request) {
    return this.requestJson('/api/generate', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }

  render(request) {
    return this.requestJson('/api/map', {
      method: 'POST',
      body: JSON.stringify(request),
    });
  }
}

// Mock mode is intentionally a separate API implementation. Its bitmap is fixed
// canned artwork, not a JavaScript interpretation of arbitrary map geometry.
const MOCK_SPEC = {
  name: 'mock-pool-00',
  genSeed: 1001,
  width: 1235,
  height: 659,
  flagRing: 70,
  captureClear: 210,
  spawnClearW: 70,
  spawnClearH: 130,
  gunRange: 1050,
  symmetry: 'mirror',
  layout: 'sides',
  endzone: 'square',
  endzoneRadius: 140,
  homeDepth: 700,
  medKitSpawns: [[617, 219], [617, 439]],
  medKitCandidates: [[617, 219], [617, 439], [617, 286], [617, 372]],
  trenches: [[250, 110, 56, 56], [929, 493, 56, 56]],
  leftObstacles: [
    { kind: 'rect', x: 245, y: 70, w: 18, h: 152 },
    { kind: 'diamond', cx: 405, cy: 167, r: 28 },
    { kind: 'disc', cx: 489, cy: 329, r: 28, window: true },
    { kind: 'diagonal', x0: 530, y0: 430, x1: 577, y1: 487, t: 12 },
  ],
};

const MOCK_DERIVED = {
  teamCount: 2,
  seedRegion: { x: 0, y: 0, w: 617, h: 659 },
  anchors: [
    { team: 'red', x: 185, y: 329 },
    { team: 'blue', x: 1049, y: 329 },
  ],
  captureZones: [
    {
      team: 'red', xLo: 45, xHi: 325, yLo: 189, yHi: 469,
      diag: false, cornerX: 0, cornerY: 0, diagLimit: 0,
      disc: false, anchorX: 185, anchorY: 329, radius: 140,
    },
    {
      team: 'blue', xLo: 909, xHi: 1189, yLo: 189, yHi: 469,
      diag: false, cornerX: 0, cornerY: 0, diagLimit: 0,
      disc: false, anchorX: 1049, anchorY: 329, radius: 140,
    },
  ],
  pickups: {
    grenade: [[50, 50], [50, 608], [1184, 50], [1184, 608]],
    shield: [[185, 399], [1049, 259]],
    plasmaArc: [[185, 259], [1049, 399]],
    medKitActive: [[617, 219], [617, 439]],
    medKitCandidate: [[617, 219], [617, 439], [617, 286], [617, 372]],
  },
  spinningDiamonds: [
    { cx: 565, cy: 252, r: 30 },
    { cx: 669, cy: 406, r: 30 },
  ],
  authoredObstacleCount: 34,
  expandedObstacleCount: 68,
};

class MockMapEditorApi {
  async getPool() {
    return { seeds: [1001, 1003, 1007], count: 3 };
  }

  async getPoolMap(index) {
    if (index < 0 || index > 2) {
      return { ok: false, error: `Mock pool index ${index} is out of range.` };
    }
    const spec = cloneJson(MOCK_SPEC);
    spec.name = `mock-pool-${String(index).padStart(2, '0')}`;
    spec.genSeed = [1001, 1003, 1007][index];
    return { ok: true, spec };
  }

  async generate(request) {
    const spec = cloneJson(MOCK_SPEC);
    spec.name = `mock-seed-${request.seed}`;
    spec.genSeed = request.seed;
    return { ok: true, spec };
  }

  async render(request) {
    if (request.spec.width !== MOCK_SPEC.width || request.spec.height !== MOCK_SPEC.height) {
      return {
        ok: false,
        error: 'Mock mode only has canned artwork for a 1235×659 px map.',
      };
    }

    const maxDimension = request.render.maxDimension;
    const scale = maxDimension === 0
      ? 1
      : Math.min(1, maxDimension / Math.max(MOCK_SPEC.width, MOCK_SPEC.height));
    const png = this.createCannedPng(scale, new Set(request.render.overlays));

    return {
      ok: true,
      png,
      renderScale: scale,
      validation: {
        valid: false,
        reason: 'open horizontal sightline at y=412',
        coverPermille: 88,
        minCoverPermille: 74,
        coverPermilleMin: 40,
        coverPermilleMax: 170,
        openSightlineRows: [412, 416, 420],
        unreachableTeams: ['blue'],
        centerReachable: true,
        endzoneGates: [
          { name: 'north', state: 'open' },
          { name: 'behind', state: 'sealed' },
        ],
      },
      derived: cloneJson(MOCK_DERIVED),
    };
  }

  createCannedPng(scale, overlays) {
    const width = Math.ceil(MOCK_SPEC.width * scale);
    const height = Math.ceil(MOCK_SPEC.height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext('2d');
    const px = (value) => value * scale;

    context.fillStyle = '#cdbfa9';
    context.fillRect(0, 0, width, height);
    context.strokeStyle = '#2c2219';
    context.lineWidth = Math.max(2, px(10));
    context.strokeRect(0, 0, width, height);

    if (overlays.has('protected')) {
      context.fillStyle = '#e4d2ad';
      context.beginPath();
      context.arc(px(617), px(329), px(70), 0, Math.PI * 2);
      context.fill();
      context.fillRect(px(45), px(189), px(280), px(280));
      context.fillRect(px(909), px(189), px(280), px(280));
    }

    context.fillStyle = '#493827';
    const rectangles = [
      [245, 70, 18, 152], [245, 437, 18, 152],
      [972, 70, 18, 152], [972, 437, 18, 152],
      [350, 277, 95, 22], [790, 360, 95, 22],
      [530, 430, 58, 14], [647, 215, 58, 14],
    ];
    for (const [x, y, w, h] of rectangles) {
      context.fillRect(px(x), px(y), px(w), px(h));
    }

    context.fillStyle = '#5c4733';
    for (const [x, y] of [[405, 167], [405, 492], [829, 167], [829, 492]]) {
      context.beginPath();
      context.moveTo(px(x), px(y - 28));
      context.lineTo(px(x + 28), px(y));
      context.lineTo(px(x), px(y + 28));
      context.lineTo(px(x - 28), px(y));
      context.closePath();
      context.fill();
    }

    context.fillStyle = '#1e8395';
    context.beginPath();
    context.arc(px(489), px(329), px(28), 0, Math.PI * 2);
    context.fill();
    context.beginPath();
    context.arc(px(745), px(329), px(28), 0, Math.PI * 2);
    context.fill();

    context.fillStyle = '#80674f';
    context.fillRect(px(250), px(110), px(56), px(56));
    context.fillRect(px(929), px(493), px(56), px(56));

    if (overlays.has('sightlines')) {
      context.strokeStyle = '#a33b32';
      context.lineWidth = Math.max(1, px(2));
      for (const y of [412, 416, 420]) {
        context.beginPath();
        context.moveTo(0, px(y));
        context.lineTo(width, px(y));
        context.stroke();
      }
    }

    if (overlays.has('reachability')) {
      context.fillStyle = 'rgba(163, 59, 50, 0.16)';
      context.fillRect(px(820), px(100), px(360), px(459));
    }

    return canvas.toDataURL('image/png').split(',')[1];
  }
}

class EditorStore {
  constructor() {
    this.listeners = new Set();
    this.state = {
      document: {
        spec: null,
        revision: 0,
        source: null,
      },
      controls: {
        overlays: new Set(['protected', 'pickups', 'spin', 'seedRegion']),
        maxDimension: 1600,
      },
      render: {
        pending: false,
        latestRequestedRevision: 0,
        renderedRequestRevision: 0,
        renderedDocumentRevision: 0,
        lastGoodResponse: null,
        lastGoodSpec: null,
        lastGoodOptions: null,
        image: null,
        imageUrl: null,
        error: null,
      },
    };
  }

  subscribe(listener) {
    this.listeners.add(listener);
    listener(this.state);
    return () => this.listeners.delete(listener);
  }

  change(mutator) {
    mutator(this.state);
    for (const listener of this.listeners) {
      listener(this.state);
    }
  }

  setDocument(spec, source) {
    this.change((state) => {
      state.document.spec = cloneJson(spec);
      state.document.source = source;
      state.document.revision += 1;
      state.render.error = null;
    });
  }
}

async function decodePng(base64) {
  let bytes;
  try {
    const binary = atob(base64);
    bytes = new Uint8Array(binary.length);
    for (let index = 0; index < binary.length; index += 1) {
      bytes[index] = binary.charCodeAt(index);
    }
  } catch (error) {
    throw new Error('The service returned invalid base64 PNG data.');
  }

  const url = URL.createObjectURL(new Blob([bytes], { type: 'image/png' }));
  const image = new Image();
  image.src = url;
  try {
    await image.decode();
  } catch (error) {
    URL.revokeObjectURL(url);
    throw new Error('The service returned PNG data the browser could not decode.');
  }
  return { image, url };
}

class RenderCoordinator {
  constructor(api, store) {
    this.api = api;
    this.store = store;
    this.timer = null;
    this.pendingRequest = null;
    this.inFlight = false;
    this.requestRevision = 0;
  }

  schedule({ immediate = false } = {}) {
    const state = this.store.state;
    if (!state.document.spec) return;

    this.requestRevision += 1;
    const request = {
      revision: this.requestRevision,
      documentRevision: state.document.revision,
      spec: cloneJson(state.document.spec),
      render: {
        maxDimension: state.controls.maxDimension,
        overlays: OVERLAY_ORDER.filter((name) => state.controls.overlays.has(name)),
      },
    };
    this.pendingRequest = request;
    this.store.change((current) => {
      current.render.latestRequestedRevision = request.revision;
      current.render.pending = true;
      current.render.error = null;
    });

    window.clearTimeout(this.timer);
    if (immediate) {
      this.drain();
      return;
    }
    this.timer = window.setTimeout(() => this.drain(), 150);
  }

  async drain() {
    window.clearTimeout(this.timer);
    if (this.inFlight || !this.pendingRequest) return;

    const request = this.pendingRequest;
    this.pendingRequest = null;
    this.inFlight = true;

    try {
      const response = await this.api.render({ spec: request.spec, render: request.render });
      if (request.revision !== this.requestRevision) return;

      if (!response || response.ok !== true) {
        const message = response && response.error
          ? response.error
          : 'The map service rejected the spec without an error message.';
        this.store.change((state) => {
          state.render.error = { kind: 'domain', message };
        });
        return;
      }

      const decoded = await decodePng(response.png);
      if (request.revision !== this.requestRevision) {
        URL.revokeObjectURL(decoded.url);
        return;
      }

      this.store.change((state) => {
        const previousUrl = state.render.imageUrl;
        state.render.lastGoodResponse = response;
        state.render.lastGoodSpec = request.spec;
        state.render.lastGoodOptions = request.render;
        state.render.image = decoded.image;
        state.render.imageUrl = decoded.url;
        state.render.renderedRequestRevision = request.revision;
        state.render.renderedDocumentRevision = request.documentRevision;
        state.render.error = null;
        if (previousUrl) URL.revokeObjectURL(previousUrl);
      });
    } catch (error) {
      if (request.revision === this.requestRevision) {
        this.store.change((state) => {
          state.render.error = {
            kind: 'transport',
            message: error instanceof Error ? error.message : String(error),
          };
        });
      }
    } finally {
      this.inFlight = false;
      const hasNewerRequest = Boolean(this.pendingRequest);
      this.store.change((state) => {
        state.render.pending = hasNewerRequest;
      });
      if (hasNewerRequest) this.drain();
    }
  }
}

class MapViewport {
  constructor(store) {
    this.store = store;
    this.viewport = $('map-viewport');
    this.mapCanvas = $('map-canvas');
    this.mapContext = this.mapCanvas.getContext('2d');
    this.overlayCanvas = $('overlay-canvas');
    this.overlayContext = this.overlayCanvas.getContext('2d');
    this.emptyState = $('empty-map');
    this.pointerStatus = $('pointer-position');
    this.zoomStatus = $('zoom-status');
    this.image = null;
    this.response = null;
    this.spec = null;
    this.appliedOverlays = new Set();
    this.zoom = 1;
    this.panX = 0;
    this.panY = 0;
    this.fitted = true;
    this.drag = null;
    this.lastRenderedDocumentRevision = 0;
    this.labelBounds = [];

    this.bindEvents();
    this.resizeObserver = new ResizeObserver(() => this.resize());
    this.resizeObserver.observe(this.viewport);
    this.store.subscribe((state) => this.updateFromState(state));
  }

  bindEvents() {
    this.viewport.addEventListener('pointerdown', (event) => {
      if (!this.image || event.button !== 0) return;
      this.drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
      this.fitted = false;
      this.viewport.classList.add('panning');
      this.viewport.setPointerCapture(event.pointerId);
    });

    this.viewport.addEventListener('pointermove', (event) => {
      this.updatePointerStatus(event);
      if (!this.drag || this.drag.pointerId !== event.pointerId) return;
      this.panX += event.clientX - this.drag.x;
      this.panY += event.clientY - this.drag.y;
      this.drag.x = event.clientX;
      this.drag.y = event.clientY;
      this.applyTransform();
    });

    const endPan = (event) => {
      if (!this.drag || this.drag.pointerId !== event.pointerId) return;
      this.drag = null;
      this.viewport.classList.remove('panning');
    };
    this.viewport.addEventListener('pointerup', endPan);
    this.viewport.addEventListener('pointercancel', endPan);
    this.viewport.addEventListener('pointerleave', () => {
      if (!this.drag) this.pointerStatus.textContent = 'Pointer outside board';
    });

    this.viewport.addEventListener('wheel', (event) => {
      if (!this.image) return;
      event.preventDefault();
      const bounds = this.viewport.getBoundingClientRect();
      const mouseX = event.clientX - bounds.left;
      const mouseY = event.clientY - bounds.top;
      const factor = Math.exp(-event.deltaY * 0.0015);
      const nextZoom = Math.min(Math.max(this.zoom * factor, 0.05), 16);
      this.panX = mouseX - (mouseX - this.panX) * (nextZoom / this.zoom);
      this.panY = mouseY - (mouseY - this.panY) * (nextZoom / this.zoom);
      this.zoom = nextZoom;
      this.fitted = false;
      this.applyTransform();
    }, { passive: false });

    this.viewport.addEventListener('dblclick', () => this.fit());
    $('fit-map').addEventListener('click', () => this.fit());
  }

  updateFromState(state) {
    const render = state.render;
    if (render.image && render.image !== this.image) {
      this.image = render.image;
      this.response = render.lastGoodResponse;
      this.spec = render.lastGoodSpec;
      this.appliedOverlays = new Set(render.lastGoodOptions.overlays);
      this.mapCanvas.width = this.image.naturalWidth;
      this.mapCanvas.height = this.image.naturalHeight;
      this.mapContext.imageSmoothingEnabled = false;
      this.mapContext.clearRect(0, 0, this.mapCanvas.width, this.mapCanvas.height);
      this.mapContext.drawImage(this.image, 0, 0);
      this.mapCanvas.style.display = 'block';
      this.emptyState.hidden = true;
      $('fit-map').disabled = false;

      if (render.renderedDocumentRevision !== this.lastRenderedDocumentRevision) {
        this.lastRenderedDocumentRevision = render.renderedDocumentRevision;
        this.fit();
      } else {
        this.applyTransform();
      }
    } else if (this.image) {
      this.drawOverlay();
    }
  }

  resize() {
    const width = this.viewport.clientWidth;
    const height = this.viewport.clientHeight;
    const ratio = window.devicePixelRatio || 1;
    this.overlayCanvas.width = Math.max(1, Math.round(width * ratio));
    this.overlayCanvas.height = Math.max(1, Math.round(height * ratio));
    this.overlayCanvas.style.width = `${width}px`;
    this.overlayCanvas.style.height = `${height}px`;
    this.overlayContext.setTransform(ratio, 0, 0, ratio, 0, 0);
    if (this.fitted && this.image) this.fit();
    else this.drawOverlay();
  }

  fit() {
    if (!this.image) return;
    const padding = 22;
    const availableWidth = Math.max(1, this.viewport.clientWidth - padding * 2);
    const availableHeight = Math.max(1, this.viewport.clientHeight - padding * 2);
    this.zoom = Math.min(
      availableWidth / this.image.naturalWidth,
      availableHeight / this.image.naturalHeight,
    );
    this.panX = (this.viewport.clientWidth - this.image.naturalWidth * this.zoom) / 2;
    this.panY = (this.viewport.clientHeight - this.image.naturalHeight * this.zoom) / 2;
    this.fitted = true;
    this.applyTransform();
  }

  applyTransform() {
    this.mapCanvas.style.transform = `translate(${this.panX}px, ${this.panY}px) scale(${this.zoom})`;
    this.zoomStatus.textContent = `Zoom ${Math.round(this.zoom * 100)}% of rendered image`;
    this.drawOverlay();
  }

  specToScreen(x, y) {
    const scale = this.response.renderScale;
    return {
      x: this.panX + x * scale * this.zoom,
      y: this.panY + y * scale * this.zoom,
    };
  }

  updatePointerStatus(event) {
    if (!this.response || !this.spec) {
      this.pointerStatus.textContent = 'Pointer outside board';
      return;
    }
    const bounds = this.viewport.getBoundingClientRect();
    const imageX = (event.clientX - bounds.left - this.panX) / this.zoom;
    const imageY = (event.clientY - bounds.top - this.panY) / this.zoom;
    const specX = Math.max(0, Math.min(this.spec.width - 1, Math.round(imageX / this.response.renderScale)));
    const specY = Math.max(0, Math.min(this.spec.height - 1, Math.round(imageY / this.response.renderScale)));
    const inside = imageX >= 0 && imageY >= 0
      && imageX < this.image.naturalWidth && imageY < this.image.naturalHeight;
    if (!inside) {
      this.pointerStatus.textContent = 'Pointer outside board';
      return;
    }

    const seed = this.response.derived && this.response.derived.seedRegion;
    const outsideSeed = seed && !(
      specX >= seed.x && specX < seed.x + seed.w
      && specY >= seed.y && specY < seed.y + seed.h
    );
    const suffix = outsideSeed ? ' · outside conventional seed guide' : '';
    this.pointerStatus.textContent = `x ${formatInteger(specX)} px · y ${formatInteger(specY)} px${suffix}`;
  }

  drawOverlay() {
    const context = this.overlayContext;
    const width = this.viewport.clientWidth;
    const height = this.viewport.clientHeight;
    context.clearRect(0, 0, width, height);
    this.labelBounds = [];
    if (!this.response || !this.spec || !this.image) return;

    context.save();
    context.beginPath();
    context.rect(
      this.panX,
      this.panY,
      this.image.naturalWidth * this.zoom,
      this.image.naturalHeight * this.zoom,
    );
    context.clip();

    if (this.appliedOverlays.has('seedRegion')) this.drawSeedRegion(context);
    this.drawCaptureZones(context);
    this.drawAnchors(context);
    if (this.appliedOverlays.has('pickups')) this.drawPickups(context);
    if (this.appliedOverlays.has('spin')) this.drawSpinningDiamonds(context);
    this.drawTrenches(context);
    context.restore();
  }

  drawSeedRegion(context) {
    const seed = this.response.derived && this.response.derived.seedRegion;
    if (!seed) return;

    const mapX = this.panX;
    const mapY = this.panY;
    const mapWidth = this.image.naturalWidth * this.zoom;
    const mapHeight = this.image.naturalHeight * this.zoom;
    const start = this.specToScreen(seed.x, seed.y);
    const end = this.specToScreen(seed.x + seed.w, seed.y + seed.h);

    context.save();
    context.beginPath();
    context.rect(mapX, mapY, mapWidth, mapHeight);
    context.rect(start.x, start.y, end.x - start.x, end.y - start.y);
    context.fillStyle = 'rgba(36, 28, 22, 0.16)';
    context.fill('evenodd');
    context.setLineDash([6, 4]);
    context.lineWidth = 1.5;
    context.strokeStyle = '#b9782d';
    context.strokeRect(start.x, start.y, end.x - start.x, end.y - start.y);
    context.restore();

    this.drawLabel(context, start.x + 8, start.y + 8, 'CONVENTIONAL SEED REGION', '#6b471c', {
      background: 'rgba(243, 237, 226, 0.92)',
      force: true,
    });
  }

  drawCaptureZones(context) {
    const zones = this.response.derived && this.response.derived.captureZones;
    if (!Array.isArray(zones)) return;

    for (const zone of zones) {
      const color = TEAM_COLORS[zone.team] || '#74675a';
      context.save();
      context.strokeStyle = color;
      context.fillStyle = `${color}1f`;
      context.lineWidth = 1.5;
      context.setLineDash([5, 4]);
      context.beginPath();

      if (zone.disc) {
        const center = this.specToScreen(zone.anchorX, zone.anchorY);
        const radius = zone.radius * this.response.renderScale * this.zoom;
        context.arc(center.x, center.y, radius, 0, Math.PI * 2);
      } else if (zone.diag) {
        const corner = this.specToScreen(zone.cornerX, zone.cornerY);
        const xDirection = zone.cornerX <= this.spec.width / 2 ? 1 : -1;
        const yDirection = zone.cornerY <= this.spec.height / 2 ? 1 : -1;
        const xEdge = this.specToScreen(zone.cornerX + xDirection * zone.diagLimit, zone.cornerY);
        const yEdge = this.specToScreen(zone.cornerX, zone.cornerY + yDirection * zone.diagLimit);
        context.moveTo(corner.x, corner.y);
        context.lineTo(xEdge.x, xEdge.y);
        context.lineTo(yEdge.x, yEdge.y);
        context.closePath();
      } else {
        const start = this.specToScreen(zone.xLo, zone.yLo);
        const end = this.specToScreen(zone.xHi + 1, zone.yHi + 1);
        context.rect(start.x, start.y, end.x - start.x, end.y - start.y);
      }
      context.fill();
      context.stroke();
      context.restore();

      const teamAnchor = (this.response.derived.anchors || [])
        .find((anchor) => anchor.team === zone.team);
      const labelX = teamAnchor ? teamAnchor.x : (zone.xLo + zone.xHi) / 2;
      const labelY = teamAnchor ? teamAnchor.y : (zone.yLo + zone.yHi) / 2;
      const labelPoint = this.specToScreen(labelX, labelY);
      this.drawLabel(context, labelPoint.x, labelPoint.y + 13, `${zone.team} capture zone`, color);
    }
  }

  drawAnchors(context) {
    const anchors = this.response.derived && this.response.derived.anchors;
    if (!Array.isArray(anchors)) return;
    for (const anchor of anchors) {
      const point = this.specToScreen(anchor.x, anchor.y);
      const color = TEAM_COLORS[anchor.team] || '#74675a';
      this.drawCrosshair(context, point.x, point.y, color, 5);
      this.drawLabel(context, point.x, point.y, `${anchor.team} pedestal`, color);
    }
  }

  drawPickups(context) {
    const pickups = this.response.derived && this.response.derived.pickups;
    if (!pickups) return;
    const labels = {
      grenade: 'grenade',
      shield: 'shield',
      plasmaArc: 'spray can',
      medKitActive: 'active med kit',
      medKitCandidate: 'med-kit candidate',
    };
    // One label per family, bare markers for the rest. A standard board repeats
    // each family two to four times, so labelling every instance buries the
    // terrain the labels exist to annotate. "Nominal" is stated once in the
    // overlay panel rather than on a dozen markers, and every exact coordinate
    // stays in the marker list below the board.
    for (const [family, points] of Object.entries(pickups)) {
      if (!Array.isArray(points)) continue;
      let labelled = false;
      for (const pointValue of points) {
        if (!Array.isArray(pointValue) || pointValue.length < 2) continue;
        const point = this.specToScreen(pointValue[0], pointValue[1]);
        const color = MARKER_COLORS[family] || '#74675a';
        this.drawMarker(context, point.x, point.y, color, family === 'medKitCandidate');
        if (!labelled) {
          this.drawLabel(
            context, point.x, point.y,
            labels[family] || humanizeToken(family), color
          );
          labelled = true;
        }
      }
    }
  }

  drawSpinningDiamonds(context) {
    const diamonds = this.response.derived && this.response.derived.spinningDiamonds;
    if (!Array.isArray(diamonds)) return;
    for (const diamond of diamonds) {
      const point = this.specToScreen(diamond.cx, diamond.cy);
      const color = MARKER_COLORS.spinningDiamond;
      context.save();
      context.strokeStyle = color;
      context.lineWidth = 1.5;
      context.strokeRect(point.x - 4, point.y - 4, 8, 8);
      context.restore();
      this.drawLabel(context, point.x, point.y, `spinning diamond · r ${diamond.r} px`, color);
    }
  }

  drawTrenches(context) {
    if (!Array.isArray(this.spec.trenches)) return;
    for (const trench of this.spec.trenches) {
      if (!Array.isArray(trench) || trench.length < 4) continue;
      const [x, y, width, height] = trench;
      const start = this.specToScreen(x, y);
      const end = this.specToScreen(x + width, y + height);
      const center = this.specToScreen(x + width / 2, y + height / 2);
      context.save();
      context.strokeStyle = MARKER_COLORS.trench;
      context.setLineDash([3, 3]);
      context.lineWidth = 1;
      context.strokeRect(start.x, start.y, end.x - start.x, end.y - start.y);
      context.restore();
      this.drawLabel(context, center.x, center.y, 'trench · read-only', MARKER_COLORS.trench);
    }
  }

  drawCrosshair(context, x, y, color, radius) {
    context.save();
    context.strokeStyle = color;
    context.lineWidth = 2;
    context.beginPath();
    context.arc(x, y, radius, 0, Math.PI * 2);
    context.moveTo(x - radius - 3, y);
    context.lineTo(x + radius + 3, y);
    context.moveTo(x, y - radius - 3);
    context.lineTo(x, y + radius + 3);
    context.stroke();
    context.restore();
  }

  drawMarker(context, x, y, color, hollow = false) {
    context.save();
    context.beginPath();
    context.arc(x, y, 4, 0, Math.PI * 2);
    context.fillStyle = hollow ? '#f3ede2' : color;
    context.fill();
    context.strokeStyle = color;
    context.lineWidth = 1.5;
    context.stroke();
    context.restore();
  }

  drawLabel(context, x, y, text, color, options = {}) {
    context.save();
    context.font = '600 10px ui-monospace, SFMono-Regular, Menlo, monospace';
    const paddingX = 4;
    const labelHeight = 17;
    const labelWidth = context.measureText(text).width + paddingX * 2;
    const offsets = options.force
      ? [[0, 0]]
      : [[8, -21], [8, 7], [-labelWidth - 8, -21], [-labelWidth - 8, 7]];
    let chosen = null;
    for (const [offsetX, offsetY] of offsets) {
      const bounds = { x: x + offsetX, y: y + offsetY, w: labelWidth, h: labelHeight };
      const mapLeft = Math.max(0, this.panX);
      const mapTop = Math.max(0, this.panY);
      const mapRight = Math.min(
        this.viewport.clientWidth,
        this.panX + this.image.naturalWidth * this.zoom,
      );
      const mapBottom = Math.min(
        this.viewport.clientHeight,
        this.panY + this.image.naturalHeight * this.zoom,
      );
      const outsideVisibleMap = bounds.x < mapLeft || bounds.y < mapTop
        || bounds.x + bounds.w > mapRight || bounds.y + bounds.h > mapBottom;
      const overlaps = this.labelBounds.some((other) => !(
        bounds.x + bounds.w < other.x || other.x + other.w < bounds.x
        || bounds.y + bounds.h < other.y || other.y + other.h < bounds.y
      ));
      if ((!outsideVisibleMap && !overlaps) || options.force) {
        chosen = bounds;
        break;
      }
    }
    if (!chosen) {
      context.restore();
      return;
    }

    this.labelBounds.push(chosen);
    context.fillStyle = options.background || 'rgba(243, 237, 226, 0.88)';
    context.fillRect(chosen.x, chosen.y, chosen.w, chosen.h);
    context.fillStyle = color;
    context.textBaseline = 'middle';
    context.fillText(text, chosen.x + paddingX, chosen.y + labelHeight / 2 + 0.5);
    context.restore();
  }
}

class InspectorView {
  constructor(store) {
    this.store = store;
    this.lastRenderedRequestRevision = -1;
    this.lastError = null;
    this.store.subscribe((state) => this.render(state));
  }

  render(state) {
    const render = state.render;
    this.renderStatus(state);
    this.renderDocumentActions(state);

    const errorKey = render.error ? `${render.error.kind}:${render.error.message}` : '';
    if (
      render.renderedRequestRevision === this.lastRenderedRequestRevision
      && errorKey === this.lastError
    ) return;

    this.lastRenderedRequestRevision = render.renderedRequestRevision;
    this.lastError = errorKey;
    this.renderValidation(state);
    this.renderSummary(state);
    this.renderDerived(state);
  }

  renderStatus(state) {
    const render = state.render;
    const status = $('render-status');
    status.classList.toggle('rendering', render.pending);
    status.classList.toggle('error', Boolean(render.error));

    if (render.error) {
      const prefix = render.error.kind === 'domain' ? 'Spec rejected' : 'Service error';
      const retained = render.lastGoodResponse ? ' · last good board retained' : '';
      status.textContent = `${prefix}: ${render.error.message}${retained}`;
      return;
    }
    if (render.pending) {
      if (render.lastGoodResponse) {
        status.textContent = `Rendering request ${render.latestRequestedRevision} · showing request ${render.renderedRequestRevision}`;
      } else {
        status.textContent = `Rendering request ${render.latestRequestedRevision}`;
      }
      return;
    }
    if (render.lastGoodResponse) {
      status.textContent = `Rendered request ${render.renderedRequestRevision} · Nim geometry`;
    } else {
      status.textContent = 'Waiting for a map';
    }
  }

  renderDocumentActions(state) {
    const hasSpec = Boolean(state.document.spec);
    $('copy-spec').disabled = !hasSpec;
    $('download-spec').disabled = !hasSpec;
  }

  renderValidation(state) {
    const error = state.render.error;
    const badge = $('validation-state');
    const reason = $('validation-reason');
    const details = $('validation-details');
    details.replaceChildren();

    if (error) {
      badge.className = 'validation-state invalid';
      badge.textContent = error.kind === 'domain' ? 'Spec error' : 'Unavailable';
      reason.textContent = error.message;
      if (state.render.lastGoodResponse) {
        appendDetail(details, 'Board shown', 'Last successful render; it does not represent the rejected spec');
      }
      return;
    }

    const validation = state.render.lastGoodResponse && state.render.lastGoodResponse.validation;
    if (!validation) {
      badge.className = 'validation-state neutral';
      badge.textContent = 'Not run';
      reason.textContent = 'Load a map to run the Nim validators.';
      return;
    }

    badge.className = `validation-state ${validation.valid ? 'valid' : 'invalid'}`;
    badge.textContent = validation.valid ? 'Play-valid' : 'Needs review';
    reason.textContent = validation.reason || (validation.valid
      ? 'The map passes all play-quality checks.'
      : 'The map did not pass validation.');

    const minimum = validation.coverPermilleMin ?? validation.minCoverPermille;
    const maximum = validation.coverPermilleMax;
    let cover = `${formatInteger(validation.coverPermille)}‰ cover`;
    if (Number.isFinite(minimum) && Number.isFinite(maximum)) {
      cover += ` · valid ${formatInteger(minimum)}–${formatInteger(maximum)}‰`;
    } else if (Number.isFinite(minimum)) {
      cover += ` · minimum ${formatInteger(minimum)}‰`;
    }
    appendDetail(details, 'Cover budget', cover);

    const rows = validation.openSightlineRows || [];
    appendDetail(
      details,
      'Sightlines',
      rows.length
        ? `${rows.length} open rows · y ${rows.map(formatInteger).join(', ')} px`
        : 'No open cross-field rows',
    );

    const unreachable = validation.unreachableTeams || [];
    appendDetail(
      details,
      'Team routes',
      unreachable.length ? `${unreachable.join(', ')} cannot reach required space` : 'All teams reachable',
    );
    appendDetail(details, 'Map center', validation.centerReachable ? 'Reachable' : 'Unreachable');

    const gates = validation.endzoneGates || [];
    appendDetail(
      details,
      'Endzone gates',
      gates.length
        ? gates.map((gate) => `${gate.name}: ${gate.state}`).join(' · ')
        : 'No compact-endzone gate results',
    );
  }

  renderSummary(state) {
    const response = state.render.lastGoodResponse;
    const spec = state.render.lastGoodSpec;
    const summary = $('map-summary');
    const source = $('document-source');
    const seedNote = $('seed-region-note');
    summary.replaceChildren();
    source.textContent = state.document.source || 'No source';

    if (!response || !spec) {
      seedNote.hidden = true;
      $('map-caption').textContent = 'Load a map to inspect the server-rendered terrain.';
      return;
    }

    const stale = state.render.renderedDocumentRevision !== state.document.revision;
    $('map-caption').textContent = stale
      ? `${spec.name || 'Unnamed map'} · showing the last accepted document revision`
      : `${spec.name || 'Unnamed map'} · full expanded board`;
    const derived = response.derived || {};
    appendDetail(summary, 'Dimensions', `${formatInteger(spec.width)} × ${formatInteger(spec.height)} map px`);
    appendDetail(summary, 'Teams', `${formatInteger(derived.teamCount)} teams · ${humanizeToken(spec.layout)} layout`);
    appendDetail(summary, 'Symmetry', humanizeToken(spec.symmetry));
    appendDetail(summary, 'Endzone', formatEndzone(spec));
    appendDetail(summary, 'Obstacles', `${formatInteger(derived.authoredObstacleCount)} authored · ${formatInteger(derived.expandedObstacleCount)} expanded`);
    appendDetail(summary, 'Trenches', `${formatInteger((spec.trenches || []).length)} full-map rectangles · read-only`);
    appendDetail(summary, 'Render scale', `${response.renderScale.toFixed(4)} image px per map px`);

    const seed = derived.seedRegion;
    if (seed) {
      seedNote.hidden = false;
      seedNote.textContent = `Conventional seed guide: x ${formatInteger(seed.x)}–${formatInteger(seed.x + seed.w - 1)} px, y ${formatInteger(seed.y)}–${formatInteger(seed.y + seed.h - 1)} px. Advisory only; authored generator shapes may cross it.`;
    } else {
      seedNote.hidden = true;
    }
  }

  renderDerived(state) {
    const response = state.render.lastGoodResponse;
    const spec = state.render.lastGoodSpec;
    const root = $('derived-markers');
    root.replaceChildren();
    if (!response || !spec || !response.derived) {
      const empty = document.createElement('p');
      empty.className = 'empty-detail';
      empty.textContent = 'No derived data yet.';
      root.append(empty);
      return;
    }

    const derived = response.derived;
    addMarkerGroup(root, 'Pedestals', (derived.anchors || []).map((anchor) => (
      `${humanizeToken(anchor.team)} pedestal · ${formatPoint(anchor.x, anchor.y)}`
    )));

    addMarkerGroup(root, 'Capture zones', (derived.captureZones || []).map((zone) => {
      const shape = zone.diag ? `diagonal · L1 limit ${zone.diagLimit} px`
        : zone.disc ? `disc · radius ${zone.radius} px`
          : `box · x ${zone.xLo}–${zone.xHi} px · y ${zone.yLo}–${zone.yHi} px`;
      return `${humanizeToken(zone.team)} · ${shape}`;
    }));

    const pickupItems = [];
    for (const [family, points] of Object.entries(derived.pickups || {})) {
      for (const point of points || []) {
        pickupItems.push(`${humanizeToken(family)} ${formatPoint(point[0], point[1])}`);
      }
    }
    addMarkerGroup(root, 'Nominal pickups', pickupItems);

    addMarkerGroup(root, 'Spinning diamonds', (derived.spinningDiamonds || []).map((diamond) => (
      `${formatPoint(diamond.cx, diamond.cy)} · L1 radius ${formatInteger(diamond.r)} px`
    )));

    addMarkerGroup(root, 'Trenches · read-only', (spec.trenches || []).map((trench) => (
      `x ${formatInteger(trench[0])} px · y ${formatInteger(trench[1])} px · ${formatInteger(trench[2])} × ${formatInteger(trench[3])} px`
    )));
  }
}

function appendDetail(list, term, description) {
  const dt = document.createElement('dt');
  dt.textContent = term;
  const dd = document.createElement('dd');
  dd.textContent = description;
  list.append(dt, dd);
}

function addMarkerGroup(root, heading, items) {
  if (!items.length) return;
  const group = document.createElement('section');
  group.className = 'marker-group';
  const title = document.createElement('h3');
  title.textContent = heading;
  const list = document.createElement('ul');
  for (const item of items) {
    const listItem = document.createElement('li');
    listItem.textContent = item;
    list.append(listItem);
  }
  group.append(title, list);
  root.append(group);
}

function formatEndzone(spec) {
  if (spec.endzone === 'column') {
    return `Column · base depth ${formatInteger(spec.homeDepth)}‰ of half-field`;
  }
  return `${humanizeToken(spec.endzone)} · radius ${formatInteger(spec.endzoneRadius)} px · base depth ${formatInteger(spec.homeDepth)}‰ of half-field`;
}

class Application {
  constructor() {
    const params = new URLSearchParams(window.location.search);
    this.mockMode = params.get('mock') === '1';
    this.api = this.mockMode ? new MockMapEditorApi() : new MapEditorApi();
    this.store = new EditorStore();
    this.coordinator = new RenderCoordinator(this.api, this.store);
    this.viewport = new MapViewport(this.store);
    this.inspector = new InspectorView(this.store);
  }

  async start() {
    this.bindSourceTabs();
    this.bindSourceControls();
    this.bindOverlayControls();
    this.bindExportControls();

    if (this.mockMode) {
      $('mock-badge').hidden = false;
      this.setConnectionStatus('Mock API active', 'connected');
    }

    try {
      const pool = await this.api.getPool();
      this.populatePool(pool);
      if (!this.mockMode) this.setConnectionStatus('Local Nim service connected', 'connected');
      await this.loadPoolMap(0);
    } catch (error) {
      this.setConnectionStatus('Local service unavailable', 'failed');
      this.showSourceError(error instanceof Error ? error.message : String(error));
    }
  }

  bindSourceTabs() {
    const tabs = Array.from(document.querySelectorAll('[data-source-tab]'));
    const selectTab = (tab, moveFocus = false) => {
      const selected = tab.dataset.sourceTab;
      for (const candidate of tabs) {
        const active = candidate === tab;
        candidate.setAttribute('aria-selected', String(active));
        candidate.tabIndex = active ? 0 : -1;
        const panel = $(`panel-${candidate.dataset.sourceTab}`)
          || (candidate.dataset.sourceTab === 'generator' ? $('generator-form') : null);
        if (panel) panel.hidden = !active;
      }
      if (moveFocus) tab.focus();
      if (selected === 'generator' && !moveFocus) $('generator-seed').focus();
      if (selected === 'json' && !moveFocus) $('spec-json').focus();
    };

    for (const tab of tabs) {
      tab.addEventListener('click', () => selectTab(tab));
      tab.addEventListener('keydown', (event) => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
        event.preventDefault();
        const currentIndex = tabs.indexOf(tab);
        let nextIndex;
        if (event.key === 'Home') nextIndex = 0;
        else if (event.key === 'End') nextIndex = tabs.length - 1;
        else if (event.key === 'ArrowRight') nextIndex = (currentIndex + 1) % tabs.length;
        else nextIndex = (currentIndex - 1 + tabs.length) % tabs.length;
        selectTab(tabs[nextIndex], true);
      });
    }
  }

  bindSourceControls() {
    $('load-pool').addEventListener('click', () => {
      this.loadPoolMap(Number.parseInt($('pool-index').value, 10));
    });

    $('generator-form').addEventListener('submit', (event) => {
      event.preventDefault();
      this.generateMap();
    });

    $('load-json').addEventListener('click', () => this.loadJsonText($('spec-json').value, 'pasted JSON'));
    $('spec-file').addEventListener('change', async (event) => {
      const [file] = event.target.files;
      if (!file) return;
      try {
        const text = await file.text();
        $('spec-json').value = text;
        this.loadJsonText(text, file.name);
      } catch (error) {
        this.showSourceError(`Could not read ${file.name}: ${error.message}`);
      }
    });

    $('render-resolution').addEventListener('change', (event) => {
      this.store.change((state) => {
        state.controls.maxDimension = Number.parseInt(event.target.value, 10);
      });
      this.coordinator.schedule({ immediate: true });
    });
  }

  bindOverlayControls() {
    for (const checkbox of document.querySelectorAll('[data-overlay]')) {
      checkbox.addEventListener('change', () => {
        this.store.change((state) => {
          if (checkbox.checked) state.controls.overlays.add(checkbox.dataset.overlay);
          else state.controls.overlays.delete(checkbox.dataset.overlay);
        });
        this.coordinator.schedule({ immediate: true });
      });
    }
  }

  bindExportControls() {
    $('copy-spec').addEventListener('click', async () => {
      const spec = this.store.state.document.spec;
      if (!spec || !this.mayExportSpec()) return;
      const text = JSON.stringify(spec, null, 2);
      try {
        await navigator.clipboard.writeText(text);
        $('copy-spec').textContent = 'Copied';
        window.setTimeout(() => { $('copy-spec').textContent = 'Copy JSON'; }, 1200);
      } catch (error) {
        this.showSourceError(`Could not copy JSON: ${error.message}`);
      }
    });

    $('download-spec').addEventListener('click', () => {
      const spec = this.store.state.document.spec;
      if (!spec || !this.mayExportSpec()) return;
      const url = URL.createObjectURL(new Blob(
        [`${JSON.stringify(spec, null, 2)}\n`],
        { type: 'application/json' },
      ));
      const link = document.createElement('a');
      link.href = url;
      link.download = fileSafeName(spec.name);
      document.body.append(link);
      link.click();
      link.remove();
      URL.revokeObjectURL(url);
    });
  }

  mayExportSpec() {
    const state = this.store.state;
    const render = state.render;
    const currentDocumentIsRendered = render.lastGoodResponse
      && render.renderedDocumentRevision === state.document.revision
      && !render.error;
    if (!currentDocumentIsRendered) {
      return window.confirm(
        'The current spec was not accepted by the Nim service. Export it verbatim anyway?',
      );
    }

    const validation = render.lastGoodResponse.validation;
    if (validation && !validation.valid) {
      const reason = validation.reason || 'The map does not pass play validation.';
      return window.confirm(`${reason}\n\nExport this play-invalid spec anyway?`);
    }
    return true;
  }

  populatePool(payload) {
    if (!payload || !Array.isArray(payload.seeds)) {
      throw new Error('The pool endpoint returned no seed list.');
    }
    const select = $('pool-index');
    select.replaceChildren();
    payload.seeds.forEach((seed, index) => {
      const option = document.createElement('option');
      option.value = String(index);
      option.textContent = `#${String(index).padStart(2, '0')} · seed ${seed}`;
      select.append(option);
    });
    select.disabled = payload.seeds.length === 0;
    $('load-pool').disabled = payload.seeds.length === 0;
  }

  async loadPoolMap(index) {
    this.clearSourceError();
    this.setSourceBusy(true);
    try {
      const response = await this.api.getPoolMap(index);
      if (!response || response.ok !== true) {
        throw new Error(response && response.error ? response.error : 'Pool map request failed.');
      }
      this.acceptSpec(response.spec, `pool #${String(index).padStart(2, '0')}`);
      $('pool-index').value = String(index);
    } catch (error) {
      this.showSourceError(error instanceof Error ? error.message : String(error));
    } finally {
      this.setSourceBusy(false);
    }
  }

  async generateMap() {
    this.clearSourceError();
    const form = $('generator-form');
    if (!form.reportValidity()) return;

    let request;
    try {
      request = {
        seed: readRequiredInteger('generator-seed'),
        teams: readRequiredInteger('generator-teams'),
        validated: $('generator-validated').checked,
        overrides: readGeneratorOverrides(),
      };
    } catch (error) {
      this.showSourceError(error.message);
      return;
    }

    this.setSourceBusy(true);
    try {
      const response = await this.api.generate(request);
      if (!response || response.ok !== true) {
        throw new Error(response && response.error ? response.error : 'Generator request failed.');
      }
      this.acceptSpec(response.spec, `generator seed ${request.seed}`);
    } catch (error) {
      this.showSourceError(error instanceof Error ? error.message : String(error));
    } finally {
      this.setSourceBusy(false);
    }
  }

  loadJsonText(text, source) {
    this.clearSourceError();
    let spec;
    try {
      spec = JSON.parse(text);
    } catch (error) {
      this.showSourceError(`Could not parse map spec JSON: ${error.message}`);
      return;
    }
    if (!spec || typeof spec !== 'object' || Array.isArray(spec)) {
      this.showSourceError('The pasted JSON must be one mapSpec object.');
      return;
    }
    this.acceptSpec(spec, source);
  }

  acceptSpec(spec, source) {
    this.clearSourceError();
    this.store.setDocument(spec, source);
    this.coordinator.schedule({ immediate: true });
  }

  setConnectionStatus(text, className) {
    const status = $('connection-status');
    status.textContent = text;
    status.className = `connection-status ${className || ''}`.trim();
  }

  setSourceBusy(busy) {
    $('load-pool').disabled = busy || $('pool-index').disabled;
    $('generator-form').querySelector('[type="submit"]').disabled = busy;
    $('load-json').disabled = busy;
    $('spec-file').disabled = busy;
  }

  showSourceError(message) {
    const error = $('source-error');
    error.textContent = message;
    error.hidden = false;
  }

  clearSourceError() {
    const error = $('source-error');
    error.textContent = '';
    error.hidden = true;
  }
}

function readRequiredInteger(id) {
  const field = $(id);
  const value = Number(field.value);
  if (!Number.isInteger(value)) {
    throw new Error(`${field.labels[0].textContent} must be an integer.`);
  }
  return value;
}

function readGeneratorOverrides() {
  const overrides = {};
  const stringFields = ['size', 'symmetry', 'centerFeature', 'layout', 'endzone'];
  const numberFields = ['columns', 'windows', 'pits', 'pitDensity', 'endzoneRadius', 'baseDepth'];

  for (const name of stringFields) {
    const value = document.querySelector(`[name="${name}"]`).value;
    if (value !== '') overrides[name] = value;
  }
  for (const name of numberFields) {
    const field = document.querySelector(`[name="${name}"]`);
    if (field.value === '') continue;
    const value = Number(field.value);
    if (!Number.isInteger(value)) {
      throw new Error(`${field.labels[0].textContent} must be an integer.`);
    }
    overrides[name] = value;
  }
  return overrides;
}

const application = new Application();
application.start();
