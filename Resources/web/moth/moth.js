/* Bartholomew's behaviour: an explicit state machine driven by page events
   and timers. It never touches artwork directly; everything visual goes
   through a renderer adapter (adapter.js). All randomness comes from one
   seedable generator. Nothing here runs until configure({enabled: true}). */
(() => {
  'use strict';

  const root = document.getElementById('doc');
  const post = (msg) => { try { window.webkit.messageHandlers.legible.postMessage(msg); } catch (_) {} };
  const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- Seedable randomness (mulberry32) -----------------------------------------
  function makeRNG(seed) {
    let a = (seed >>> 0) || 0x9e3779b9;
    const next = () => {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
    return { next, between: (lo, hi) => lo + (hi - lo) * next(), pick: (list) => list[Math.floor(next() * list.length)] };
  }

  // ---- Time (scaled for testing; pauses while the window is hidden) -------------
  const clock = {
    scale: 1,
    timers: new Set(),
    after(ms, fn) {
      const handle = { fn, due: performance.now() + ms / this.scale, id: 0 };
      const arm = () => {
        handle.id = setTimeout(() => {
          this.timers.delete(handle);
          if (document.hidden) { handle.due = performance.now() + 250; this.timers.add(handle); arm(); return; }
          fn();
        }, Math.max(0, handle.due - performance.now()));
      };
      this.timers.add(handle);
      arm();
      return handle;
    },
    cancel(handle) { if (handle) { clearTimeout(handle.id); this.timers.delete(handle); } },
    cancelAll() { for (const h of this.timers) clearTimeout(h.id); this.timers.clear(); },
    seconds(s) { return s * 1000; },
  };

  // ---- Geometry ---------------------------------------------------------------------
  const pageRect = (el) => {
    const r = el.getBoundingClientRect();
    return { left: r.left + window.scrollX, top: r.top + window.scrollY, right: r.right + window.scrollX, bottom: r.bottom + window.scrollY, width: r.width, height: r.height };
  };
  const intersects = (a, b, pad = 0) => !(a.right + pad <= b.left || a.left - pad >= b.right || a.bottom + pad <= b.top || a.top - pad >= b.bottom);

  let textRects = null;
  function collectTextRects() {
    const rects = [];
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: (node) => {
        if (!node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        const p = node.parentElement;
        if (!p || p.closest('.copy, .moth, .moth-evidence, .front-matter[open] pre')) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      },
    });
    const range = document.createRange();
    let node;
    while ((node = walker.nextNode())) {
      range.selectNodeContents(node);
      for (const r of range.getClientRects()) {
        if (r.width === 0 || r.height === 0) continue;
        rects.push({ left: r.left + window.scrollX, top: r.top + window.scrollY, right: r.right + window.scrollX, bottom: r.bottom + window.scrollY });
      }
    }
    // Images and the copy buttons count as things not to cover either.
    for (const el of root.querySelectorAll('img, .copy, input')) {
      const r = pageRect(el);
      if (r.width > 0) rects.push(r);
    }
    return rects;
  }
  function getTextRects() { return textRects || (textRects = collectTextRects()); }
  function invalidateGeometry() { textRects = null; }

  // ---- Perches -----------------------------------------------------------------------
  // A perch is described by what it sits on, so it survives re-renders:
  // {kind, index, ratio, side}. resolvePerch turns that into a page point.

  const FURNITURE = [
    { kind: 'code', selector: '.code-block', edge: 'top' },
    { kind: 'heading', selector: 'h1, h2', edge: 'bottom' },
    { kind: 'table', selector: 'table', edge: 'top' },
    { kind: 'hr', selector: 'hr', edge: 'top' },
    { kind: 'image', selector: 'img', edge: 'corner' },
    { kind: 'margin', selector: 'p, li, blockquote', edge: 'margin' },
  ];

  function furnitureElements(kind) {
    const f = FURNITURE.find((x) => x.kind === kind);
    return f ? [...root.querySelectorAll(f.selector)].filter((el) => !el.closest('.moth, .moth-evidence')) : [];
  }

  function columnRect() { return pageRect(root); }

  /** Every candidate perch point for the current layout, with the moth's rect there. */
  function candidatePerches(moth) {
    const w = moth.element.offsetWidth || moth.size, h = moth.element.offsetHeight || moth.size;
    const feet = moth.anchors.feet;
    const column = columnRect();
    const rectAt = (x, y) => ({ left: x - feet[0], top: y - h, right: x - feet[0] + w, bottom: y });
    const out = [];
    const push = (perch, x, y, bright) => out.push({ perch, x, y, rect: rectAt(x, y), bright: !!bright });

    for (const f of FURNITURE) {
      furnitureElements(f.kind).forEach((el, index) => {
        const r = pageRect(el);
        if (r.width < w + 8 || r.height === 0) return;
        const bright = f.kind === 'image' || f.kind === 'code';
        if (f.edge === 'top' || f.edge === 'bottom') {
          const y = f.edge === 'top' ? r.top : r.bottom;
          for (const ratio of [0.12, 0.3, 0.5, 0.7, 0.88]) {
            const x = r.left + r.width * ratio;
            if (f.kind === 'code' && x > r.right - 90) continue;   // leave the copy button alone
            push({ kind: f.kind, index, ratio }, x, y, bright);
          }
        } else if (f.edge === 'corner') {
          push({ kind: f.kind, index, ratio: 0, side: 'left' }, r.left + feet[0], r.top, bright);
          push({ kind: f.kind, index, ratio: 1, side: 'right' }, r.right - (w - feet[0]), r.top, bright);
        } else if (f.edge === 'margin') {
          if (el.closest('li') !== el && el.tagName === 'LI' && el.querySelector('li')) return;
          const y = r.bottom - 2;
          if (column.left - 10 >= w) push({ kind: 'margin', index, ratio: 0, side: 'left' }, column.left - 10 - (w - feet[0]), y, false);
          if (window.innerWidth - column.right - 10 >= w) push({ kind: 'margin', index, ratio: 0, side: 'right' }, column.right + 10 + feet[0], y, false);
        }
      });
    }
    // Page edges are always available (used for watching the editor, and as a last resort).
    const edgeY = window.scrollY + window.innerHeight * 0.45;
    if (column.left - 6 >= w) push({ kind: 'edge', index: 0, ratio: 0, side: 'left' }, 6 + feet[0], edgeY, false);
    return out;
  }

  function perchIsClear(candidate) {
    const rects = getTextRects();
    for (const r of rects) if (intersects(candidate.rect, r, 2)) return false;
    return candidate.rect.left >= 0 && candidate.rect.right <= document.documentElement.scrollWidth && candidate.rect.top >= 0;
  }

  function resolvePerch(perch, moth) {
    if (!perch) return null;
    const all = candidatePerches(moth);
    const exact = all.find((c) => c.perch.kind === perch.kind && c.perch.index === perch.index && c.perch.ratio === perch.ratio && c.perch.side === perch.side);
    if (exact && perchIsClear(exact)) return exact;
    const same = all.filter((c) => c.perch.kind === perch.kind && perchIsClear(c));
    if (same.length) return same.reduce((best, c) => Math.abs(c.perch.index - perch.index) < Math.abs(best.perch.index - perch.index) ? c : best);
    return null;
  }

  /** Best perch near a page y (the reading line), avoiding text; dark themes prefer bright furniture. */
  function choosePerch(moth, nearY, rng, options = {}) {
    const dark = isDarkTheme();
    const clear = candidatePerches(moth).filter((c) => c.perch.kind !== 'edge' && perchIsClear(c));
    if (!clear.length) return null;
    const scored = clear.map((c) => {
      let score = Math.abs(c.y - nearY);
      if (dark && c.bright) score -= 220;
      if (c.perch.kind === 'margin') score += 40;
      if (options.avoid && c.perch.kind === options.avoid.kind && c.perch.index === options.avoid.index) score += 1000;
      score += rng.between(0, 60);
      return { c, score };
    }).sort((a, b) => a.score - b.score);
    return scored[Math.min(scored.length - 1, Math.floor(rng.next() * Math.min(3, scored.length)))].c;
  }

  function isDarkTheme() {
    const css = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim();
    const m = /^#([0-9a-f]{6})$/i.exec(css);
    if (!m) return false;
    const [r, g, b] = m[1].match(/../g).map((h) => parseInt(h, 16) / 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.35;
  }

  // ---- Scroll cadence -------------------------------------------------------------------
  const cadence = {
    samples: [],           // {t, y}
    steadySince: null,
    lastFling: 0,
    record(y) {
      const t = performance.now();
      this.samples.push({ t, y });
      if (this.samples.length > 60) this.samples.shift();
      const prev = this.samples[this.samples.length - 2];
      if (prev) {
        const dy = Math.abs(y - prev.y), dt = t - prev.t;
        if (dt < 300 && dy > window.innerHeight * 1.5) { this.lastFling = t; this.steadySince = null; return 'fling'; }
        if (dy > window.innerHeight * 0.7) { this.steadySince = null; return 'jump'; }
      }
      if (this.steadySince === null) this.steadySince = t;
      return 'steady';
    },
    steadyFor() { return this.steadySince === null ? 0 : (performance.now() - this.steadySince) * clock.scale; },
    reset() { this.steadySince = null; },
  };

  // ---- The moth ---------------------------------------------------------------------------
  const M = {
    enabled: false,
    adapter: null,
    config: {},
    rng: makeRNG(1),
    state: 'held',
    perch: null,
    perchPoint: null,
    homePerch: null,     // where to return after watching the editor
    timers: {},
    lastActivity: performance.now(),
    idleBatches: 0,
    droppings: [],
    nibbleShown: false,
    findOpen: false,
    editorOpen: false,
    atEnd: false,
    mark: null,
    log: [],

    note(what) { this.log.push(what); if (this.log.length > 40) this.log.shift(); },

    // -- lifecycle
    configure(cfg) {
      const wasEnabled = this.enabled;
      this.config = cfg || {};
      this.enabled = !!cfg && !!cfg.enabled && !!cfg.manifest;
      clock.scale = (cfg && cfg.timeScale) || 1;
      if (cfg && cfg.seed !== undefined) this.rng = makeRNG(cfg.seed);
      if (!this.enabled) { this.teardown(); return; }
      if (!this.adapter || this.adapter.manifest !== cfg.manifest) {
        this.teardown(true);
        this.adapter = window.MothAdapters.create(cfg.manifest, cfg.asset);
        document.body.appendChild(this.adapter.element);
        this.adapter.hit.addEventListener('click', (e) => this.event('poke', { x: e.pageX, y: e.pageY }));
        if (this.adapter.setVariants) this.adapter.setVariants(cfg.variants);
      }
      this.adapter.setPalette(cfg.palette || {});
      this.adapter.setScale(cfg.scale || 1);
      this.ensureMark();
      if (!wasEnabled || this.state === 'held') this.begin();
      else this.reposition();
    },

    teardown(keepLog) {
      clock.cancelAll();
      this.timers = {};
      if (this.adapter) { this.adapter.cancelFlight(); this.adapter.element.remove(); this.adapter = null; }
      if (this.mark) { this.mark.remove(); this.mark = null; }
      for (const el of document.querySelectorAll('.moth-evidence')) el.remove();
      this.droppings = [];
      this.state = 'held';
      this.perch = null;
      cadence.reset();
    },

    begin() {
      const bookmark = this.config.bookmark;
      invalidateGeometry();
      this.setState('absent');
      this.adapter.setVisible(false);
      if (bookmark && bookmark.line !== undefined) {
        // Already perched where the reading left off; no fly-in.
        const y = yForLine(bookmark.line) ?? window.scrollY + window.innerHeight * 0.4;
        const perch = choosePerch(this.adapter, y, this.rng);
        if (perch) { this.settle(perch, { immediate: true }); }
      } else {
        this.schedule('arrive', clock.seconds(this.rng.between(18, 40)), () => this.arrive());
      }
      this.maybeNibble();
      this.schedule('tick', clock.seconds(5), () => this.tick());
    },

    setState(s) { this.state = s; this.note(s); this.adapter.element.dataset.state = s; },

    schedule(name, ms, fn) {
      clock.cancel(this.timers[name]);
      this.timers[name] = clock.after(ms, () => { delete this.timers[name]; fn(); });
    },

    // -- perching
    settle(candidate, { immediate } = {}) {
      this.perch = candidate.perch;
      this.perchPoint = { x: candidate.x, y: candidate.y };
      this.adapter.setVisible(true);
      if (immediate) {
        this.adapter.moveTo(this.perchPoint);
        this.adapter.setPose(this.atEnd ? 'close-book' : 'perch-reading');
        this.setState('perched');
        this.updateMark();
        post({ type: 'moth', event: 'perch', line: currentLine() });
        return;
      }
      this.setState('flying');
      this.adapter.setPose('fly');
      this.adapter.flyTo(this.perchPoint, 'arc', () => {
        this.adapter.setPose('land').then(() => {
          if (this.state !== 'flying') return;
          this.adapter.setPose(this.atEnd ? 'close-book' : 'perch-reading');
          this.setState('perched');
          this.updateMark();
          post({ type: 'moth', event: 'perch', line: currentLine() });
        });
      });
    },

    arrive() {
      if (this.state !== 'absent') return;
      const y = window.scrollY + window.innerHeight * 0.4;
      const perch = choosePerch(this.adapter, y, this.rng);
      if (!perch) { this.schedule('arrive', clock.seconds(20), () => this.arrive()); return; }
      const edge = nearestEdgePoint(perch);
      this.adapter.moveTo(edge);
      this.settle(perch);
    },

    /** Called after a re-render or resize: keep the same perch if it still exists. */
    reposition() {
      if (!this.adapter) return;
      invalidateGeometry();
      if (this.state === 'absent' || this.state === 'held') return;
      const target = this.state === 'watching-editor' ? this.editorPerch() : resolvePerch(this.perch, this.adapter);
      if (target) { this.perch = target.perch; this.perchPoint = { x: target.x, y: target.y }; this.adapter.moveTo(this.perchPoint); }
      else {
        const alt = choosePerch(this.adapter, this.perchPoint ? this.perchPoint.y : window.scrollY, this.rng);
        if (alt) { this.perch = alt.perch; this.perchPoint = { x: alt.x, y: alt.y }; this.adapter.moveTo(this.perchPoint); }
      }
      for (const d of this.droppings) placeSpeck(d);
      this.updateMark();
    },

    relocateIfReadingSteadily() {
      if (this.state !== 'perched' && this.state !== 'dozing') return;
      if (isShortDocument()) return;
      if (this.perchPoint && this.mothInView()) return;
      const needed = this.relocateAfter || (this.relocateAfter = clock.seconds(this.rng.between(60, 120)));
      if (cadence.steadyFor() < needed) return;
      this.relocateAfter = null;
      cadence.reset();
      const y = window.scrollY + window.innerHeight * 0.4;
      const perch = choosePerch(this.adapter, y, this.rng, { avoid: this.perch });
      if (!perch) return;
      this.adapter.moveTo(nearestEdgePoint(perch));
      this.note('relocate');
      this.settle(perch);
    },

    mothInView() {
      if (!this.perchPoint) return false;
      const top = this.perchPoint.y - this.adapter.size, bottom = this.perchPoint.y;
      return bottom > window.scrollY && top < window.scrollY + window.innerHeight;
    },

    editorPerch() {
      const all = candidatePerches(this.adapter);
      const y = window.scrollY + window.innerHeight * 0.45;
      const edge = all.find((c) => c.perch.kind === 'edge');
      if (edge) return { ...edge, y, rect: { ...edge.rect, top: y - this.adapter.size, bottom: y } };
      const margins = all.filter((c) => c.perch.kind === 'margin' && c.perch.side === 'left' && perchIsClear(c));
      if (!margins.length) return null;
      return margins.reduce((best, c) => Math.abs(c.y - y) < Math.abs(best.y - y) ? c : best);
    },

    // -- reactions
    reactWith(pose, ms, then) {
      if (!this.adapter || this.state === 'absent' || this.state === 'flying') return;
      const back = this.state === 'watching-editor' ? 'perch-idle' : (this.atEnd ? 'close-book' : 'perch-reading');
      const previous = this.state;
      this.setState('reacting');
      this.adapter.setPose(pose);
      this.schedule('reaction', ms, () => {
        if (this.state !== 'reacting') return;
        this.setState(previous === 'dozing' ? 'perched' : previous);
        if (this.findOpen) this.adapter.setPose('magnifier');
        else this.adapter.setPose(back);
        if (then) then();
      });
    },

    event(name, payload = {}) {
      if (!this.enabled || !this.adapter) return;
      this.lastActivity = performance.now();
      if (this.state === 'dozing' && name !== 'tick') {
        this.setState('perched');
        this.adapter.setPose('wake');
        this.schedule('wakeup', 500, () => { if (this.state === 'perched') this.adapter.setPose(this.findOpen ? 'magnifier' : (this.atEnd ? 'close-book' : 'perch-reading')); });
      }
      switch (name) {
        case 'scroll': {
          const kind = cadence.record(window.scrollY);
          if (kind === 'fling' && this.state === 'perched') {
            this.reactWith('cling', 700, () => { this.adapter.setPose('smooth-down'); this.schedule('smooth', 500, () => { if (this.state === 'perched') this.adapter.setPose(this.atEnd ? 'close-book' : 'perch-reading'); }); });
          } else if (kind === 'jump' && payload.atEnd && this.state === 'perched' && !this.atEnd) {
            this.atEnd = true;
            this.reactWith('disapprove', 1200);
          }
          if (payload.atEnd !== undefined && payload.atEnd !== this.atEnd) {
            this.atEnd = payload.atEnd;
            if (this.state === 'perched') this.adapter.setPose(this.atEnd ? 'close-book' : 'perch-reading');
          }
          this.updateMark();
          break;
        }
        case 'copy': this.reactWith('nod', 900); break;
        case 'find-open': this.findOpen = true; if (this.state === 'perched') this.adapter.setPose('magnifier'); break;
        case 'find-close': this.findOpen = false; if (this.state === 'perched') this.adapter.setPose(this.atEnd ? 'close-book' : 'perch-reading'); break;
        case 'reload':
          for (const d of this.droppings) d.el.remove();
          this.droppings = []; this.idleBatches = 0;
          this.reactWith('startled', 1000, () => { this.adapter.lookAt(0, window.scrollY); this.schedule('look', 400, () => this.adapter.lookNeutral()); });
          break;
        case 'editor-open':
          this.editorOpen = true;
          if (this.state === 'perched' || this.state === 'dozing' || this.state === 'reacting') {
            this.homePerch = this.perch;
            const target = this.editorPerch();
            if (target) {
              this.setState('flying');
              this.adapter.setPose('fly');
              this.adapter.flyTo({ x: target.x, y: target.y }, 'arc', () => {
                this.perch = target.perch; this.perchPoint = { x: target.x, y: target.y };
                this.adapter.setPose('perch-idle');
                this.adapter.lookAt(0, target.y);
                this.setState('watching-editor');
              });
            }
          }
          break;
        case 'editor-close':
          this.editorOpen = false;
          if (this.state === 'watching-editor') {
            this.adapter.lookNeutral();
            const home = resolvePerch(this.homePerch, this.adapter) || choosePerch(this.adapter, window.scrollY + window.innerHeight * 0.4, this.rng);
            if (home) this.settle(home); else this.setState('perched');
          }
          break;
        case 'external-link': this.reactWith('wave', 900); break;
        case 'selection': {
          if (this.state !== 'perched') break;
          this.reactWith('glance', 1500);
          if (payload.x !== undefined) { this.adapter.lookAt(payload.x, payload.y); this.schedule('look', 1500, () => this.adapter.lookNeutral()); }
          break;
        }
        case 'poke': {
          this.reactWith('startled', 600);
          this.adapter.lookAt(payload.x, payload.y);
          this.schedule('look', 800, () => this.adapter.lookNeutral());
          break;
        }
        case 'activity': break;
        default: break;
      }
    },

    // -- timers
    tick() {
      this.schedule('tick', clock.seconds(5), () => this.tick());
      if (document.hidden) return;
      const idle = (performance.now() - this.lastActivity) * clock.scale;
      if (this.state === 'perched' && idle >= clock.seconds(30)) {
        const hour = new Date().getHours();
        const late = hour >= 23 || hour < 4;
        this.setState('dozing');
        if (late && !reduceMotion()) { this.adapter.setPose('yawn'); this.schedule('yawn', 800, () => { if (this.state === 'dozing') this.adapter.setPose('doze'); }); }
        else this.adapter.setPose('doze');
      }
      if ((this.state === 'dozing' || this.state === 'perched') && idle >= clock.seconds(300) * (this.idleBatches + 1)) {
        this.idleBatches += 1;
        this.leaveDroppings();
      }
      if (this.state === 'perched' && cadence.steadyFor() > clock.seconds(45) && this.mothInView() && !this.findOpen && !this.atEnd) {
        if (!this.nextPageTurn) this.nextPageTurn = performance.now() + clock.seconds(this.rng.between(45, 90)) / clock.scale;
        if (performance.now() >= this.nextPageTurn) {
          this.nextPageTurn = null;
          this.adapter.setPose('page-turn').then(() => { if (this.state === 'perched') this.adapter.setPose('perch-reading'); });
        }
      }
      if (this.state === 'perched' && !reduceMotion() && this.rng.next() < 0.15) this.adapter.blink();
      this.relocateIfReadingSteadily();
    },

    // -- evidence
    leaveDroppings() {
      if (this.config.housetrained || !this.perchPoint) return;
      const count = 1 + Math.floor(this.rng.next() * 3);
      for (let i = 0; i < count && this.droppings.length < 6; i++) {
        const column = columnRect();
        const w = this.adapter.element.offsetWidth;
        const leftBand = column.left - 8 >= 46 ? [column.left - 44, column.left - 8] : null;
        const rightBand = window.innerWidth - column.right - 8 >= 46 ? [column.right + 8, column.right + 44] : null;
        const bands = [leftBand, rightBand].filter(Boolean);
        if (!bands.length) return;
        const band = this.rng.pick(bands);
        const speck = { x: this.rng.between(band[0], band[1]), y: this.perchPoint.y + this.rng.between(-24, 24), size: 2 + Math.round(this.rng.next()), el: null };
        speck.dx = speck.x - column.left; speck.dy = speck.y - this.perchPoint.y;
        placeSpeck(speck);
        this.droppings.push(speck);
        void w;
      }
      this.note('droppings');
    },

    maybeNibble() {
      if (this.nibbleShown || !this.config.allowNibble) return;
      if (this.rng.next() >= 0.01) return;
      this.showNibble();
    },

    showNibble() {
      if (this.nibbleShown) return;
      this.nibbleShown = true;
      const column = columnRect();
      const side = column.left >= 30 ? 'left' : (window.innerWidth - column.right >= 30 ? 'right' : null);
      if (!side) return;
      const y = this.rng.between(column.top + 80, Math.max(column.top + 120, column.bottom - 80));
      const el = document.createElement('div');
      el.className = 'moth-evidence moth-nibble';
      el.setAttribute('aria-hidden', 'true');
      const flip = side === 'right' ? 'transform="scale(-1 1) translate(-24 0)"' : '';
      el.innerHTML = `<svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true"><g ${flip}>
        <path d="M0 4 C6 4, 9 6, 9 10 C9 14, 6 16, 0 16" fill="var(--bg)" stroke="var(--fg-muted)" stroke-width="1" stroke-dasharray="1.5 1.5"/>
        <circle cx="13" cy="8" r="1" fill="var(--fg-muted)"/><circle cx="16" cy="13" r="0.8" fill="var(--fg-muted)"/></g></svg>`;
      el.style.left = `${side === 'left' ? column.left - 4 : column.right - 20}px`;
      el.style.top = `${y}px`;
      document.body.appendChild(el);
      this.note('nibble');
      post({ type: 'moth', event: 'nibble' });
    },

    // -- scroll-track mark
    ensureMark() {
      if (this.mark) return;
      const mark = document.createElement('button');
      mark.className = 'moth-mark';
      mark.type = 'button';
      mark.setAttribute('aria-label', 'Scroll to the moth');
      mark.addEventListener('click', () => {
        if (!this.perchPoint) return;
        window.scrollTo({ top: Math.max(0, this.perchPoint.y - window.innerHeight * 0.4), behavior: reduceMotion() ? 'instant' : 'smooth' });
      });
      document.body.appendChild(mark);
      this.mark = mark;
      this.updateMark();
    },

    updateMark() {
      if (!this.mark) return;
      const show = this.perchPoint && (this.state === 'perched' || this.state === 'dozing' || this.state === 'reacting') && !this.mothInView();
      this.mark.style.display = show ? '' : 'none';
      if (show) {
        const fraction = this.perchPoint.y / Math.max(1, document.documentElement.scrollHeight);
        this.mark.style.top = `${Math.round(fraction * (window.innerHeight - 16))}px`;
      }
    },

    // -- debugging and tests
    debug: {
      force(pose) { if (M.adapter) { clock.cancel(M.timers.reaction); M.setState('perched'); M.adapter.setPose(pose); } },
      event(name, payload) { M.event(name, payload); },
      timeScale(n) { clock.scale = n; },
      arrive() { if (M.state === 'absent') M.arrive(); else { M.setState('absent'); M.arrive(); } },
      place() {
        if (!M.adapter) return;
        clock.cancel(M.timers.arrive);
        const perch = choosePerch(M.adapter, window.scrollY + window.innerHeight * 0.4, M.rng);
        if (perch) M.settle(perch, { immediate: true });
      },
      relocate() { M.relocateAfter = 0; cadence.steadySince = performance.now() - 1e9; M.relocateIfReadingSteadily(); },
      droppings() { M.leaveDroppings(); },
      nibble() { M.nibbleShown = false; M.showNibble(); },
      doze() { M.lastActivity = -1e12; M.tick(); },
      status() { return { state: M.state, perch: M.perch, point: M.perchPoint, droppings: M.droppings.length, nibble: M.nibbleShown, log: M.log.slice() }; },
    },

    test: {
      /** Every clear perch candidate must avoid text; returns counts and any offenders. */
      checkPerches() {
        if (!M.adapter) return { error: 'moth not enabled' };
        invalidateGeometry();
        const all = candidatePerches(M.adapter).filter((c) => c.perch.kind !== 'edge');
        const clear = all.filter(perchIsClear);
        const rects = getTextRects();
        const offenders = clear.filter((c) => rects.some((r) => intersects(c.rect, r, 0)));
        // Detector sanity: a moth dropped onto the middle of a paragraph must be rejected,
        // and the text geometry must actually cover the document.
        const para = root.querySelector('p');
        const pr = para ? pageRect(para) : null;
        const w = M.adapter.element.offsetWidth, h = M.adapter.element.offsetHeight;
        const onText = pr ? { rect: { left: pr.left + 4, top: pr.top, right: pr.left + 4 + w, bottom: pr.top + h } } : null;
        const detectorRejectsText = onText ? !perchIsClear(onText) : false;
        return { candidates: all.length, clear: clear.length, offenders: offenders.map((c) => c.perch), textRects: rects.length, detectorRejectsText };
      },
      droppingsCap() {
        if (!M.adapter) return { error: 'moth not enabled' };
        const saved = M.config.housetrained;
        M.config.housetrained = false;
        if (!M.perchPoint) M.perchPoint = { x: columnRect().left + 100, y: window.scrollY + 200 };
        for (let i = 0; i < 10; i++) M.leaveDroppings();
        const n = M.droppings.length;
        for (const d of M.droppings) d.el.remove();
        M.droppings = [];
        M.config.housetrained = true;
        M.leaveDroppings();
        const housetrained = M.droppings.length;
        M.config.housetrained = saved;
        return { afterTenBatches: n, whileHousetrained: housetrained };
      },
      nibbleRate(runs) {
        let hits = 0;
        for (let seed = 1; seed <= runs; seed++) { const r = makeRNG(seed); if (r.next() < 0.01) hits++; }
        return { runs, hits, rate: hits / runs };
      },
    },
  };

  // ---- helpers -------------------------------------------------------------------------------
  function isShortDocument() { return document.documentElement.scrollHeight <= window.innerHeight * 2.2; }

  function nearestEdgePoint(target) {
    const vx = target.x - window.scrollX, vy = target.y - window.scrollY;
    const dLeft = vx, dRight = window.innerWidth - vx, dTop = vy, dBottom = window.innerHeight - vy;
    const min = Math.min(dLeft, dRight, dTop, dBottom);
    if (min === dLeft) return { x: window.scrollX - 40, y: target.y };
    if (min === dRight) return { x: window.scrollX + window.innerWidth + 40, y: target.y };
    if (min === dTop) return { x: target.x, y: window.scrollY - 40 };
    return { x: target.x, y: window.scrollY + window.innerHeight + 40 };
  }

  function placeSpeck(speck) {
    const column = columnRect();
    if (!speck.el) {
      speck.el = document.createElement('div');
      speck.el.className = 'moth-evidence moth-speck';
      speck.el.setAttribute('aria-hidden', 'true');
      speck.el.style.width = speck.el.style.height = `${speck.size}px`;
      document.body.appendChild(speck.el);
    }
    const y = (M.perchPoint ? M.perchPoint.y : speck.y) + speck.dy;
    speck.el.style.left = `${Math.round(column.left + speck.dx)}px`;
    speck.el.style.top = `${Math.round(y)}px`;
  }

  function currentLine() { return window.Legible && window.Legible.topLine ? window.Legible.topLine() : 0; }

  function yForLine(line) {
    const items = [...root.querySelectorAll('[data-line]')].map((el) => ({ line: Number(el.dataset.line), top: pageRect(el).top }))
      .filter((e) => Number.isFinite(e.line)).sort((a, b) => a.line - b.line);
    if (!items.length) return null;
    let prev = items[0];
    for (const it of items) { if (it.line > line) break; prev = it; }
    return prev.top;
  }

  // ---- page hooks --------------------------------------------------------------------------------
  window.addEventListener('scroll', () => {
    if (!M.enabled) return;
    const atEnd = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
    M.event('scroll', { atEnd });
  }, { passive: true });
  window.addEventListener('resize', () => { if (M.enabled) M.reposition(); });
  for (const type of ['keydown', 'pointerdown', 'wheel']) window.addEventListener(type, () => { if (M.enabled) M.lastActivity = performance.now(); }, { passive: true });
  document.addEventListener('selectionchange', () => {
    if (!M.enabled) return;
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed || !sel.rangeCount) return;
    const r = sel.getRangeAt(0).getBoundingClientRect();
    if (r.width === 0 && r.height === 0) return;
    clock.cancel(M.timers.selection);
    M.timers.selection = clock.after(400, () => M.event('selection', { x: r.left + window.scrollX + r.width / 2, y: r.top + window.scrollY + r.height / 2 }));
  });

  window.LegibleMoth = {
    configure: (cfg) => M.configure(cfg),
    event: (name, payload) => M.event(name, payload),
    afterRender: () => M.reposition(),
    status: () => M.debug.status(),
    debug: M.debug,
    test: M.test,
  };
})();
