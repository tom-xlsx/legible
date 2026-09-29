/* Moth renderer adapters. The behaviour module (moth.js) only ever calls the
   interface below; an adapter turns those calls into pixels for one kind of
   art pack (see Resources/moth/PACK-GUIDE.md).

   Interface:
     element                      the DOM node (absolutely positioned in page coordinates)
     size                         rendered height in CSS px at scale 1
     anchors                      {feet:[x,y], centre, eyeLeft, eyeRight, book} in CSS px at scale 1
     setPose(name, {transition})  show a named pose; returns a promise that resolves when a
                                  one-shot pose (page-turn etc.) has finished its cycle
     lookAt(x, y) / lookNeutral() eye direction, page coordinates
     blink()
     flyTo(point, path, done)     move the feet anchor to a page point along a path
     land() / takeOff()           short poses around a flight
     setScale(n), setPalette(tokens), setVisible(bool)
     moveTo(point)                place the feet anchor at a page point immediately
     footPoint()                  current feet position in page coordinates
*/
(() => {
  'use strict';

  const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  class BaseAdapter {
    constructor(manifest) {
      this.manifest = manifest;
      this.scale = 1;
      this.element = document.createElement('div');
      this.element.className = 'moth';
      this.element.setAttribute('aria-hidden', 'true');
      this.hit = document.createElement('div');
      this.hit.className = 'moth-hit';
      this.element.appendChild(this.hit);
      this.position = { x: 0, y: 0 };
      this.visible = false;
      this.flight = null;
    }

    get size() { return this._size * this.scale; }
    get anchors() {
      const out = {};
      for (const [k, v] of Object.entries(this._anchors)) out[k] = [v[0] * this.scale, v[1] * this.scale];
      return out;
    }

    setScale(n) {
      this.scale = n;
      this.element.style.setProperty('--moth-scale', String(n));
      this.moveTo(this.position);
    }

    setPalette(tokens) {
      for (const [k, v] of Object.entries(tokens || {})) this.element.style.setProperty(`--${k}`, v);
    }

    setVisible(flag) {
      this.visible = !!flag;
      this.element.style.display = flag ? '' : 'none';
    }

    /** Place the feet anchor at a page point. */
    moveTo(point) {
      this.position = { x: point.x, y: point.y };
      const feet = this.anchors.feet;
      this.element.style.left = `${Math.round(point.x - feet[0])}px`;
      this.element.style.top = `${Math.round(point.y - feet[1])}px`;
    }

    footPoint() { return { ...this.position }; }

    /** Fly the feet anchor to `point`; `path` is 'arc' or 'straight'. Under Reduce Motion it just appears there. */
    flyTo(point, path, done) {
      this.cancelFlight();
      const from = { ...this.position };
      // No animation under Reduce Motion, when not shown, or when nobody can see the page
      // (animation frames do not run in a hidden page, so a flight would never finish).
      if (reduceMotion() || !this.visible || document.hidden) {
        this.moveTo(point);
        if (done) done();
        return;
      }
      const distance = Math.hypot(point.x - from.x, point.y - from.y);
      const duration = Math.min(900, Math.max(350, distance * 0.9));
      const lift = path === 'arc' ? Math.min(140, 40 + distance * 0.25) : 0;
      const start = performance.now();
      const step = (now) => {
        const t = Math.min(1, (now - start) / duration);
        const e = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;   // ease in-out
        const x = from.x + (point.x - from.x) * e;
        const y = from.y + (point.y - from.y) * e - Math.sin(Math.PI * e) * lift;
        this.moveTo({ x, y });
        if (t < 1) this.flight = requestAnimationFrame(step);
        else { this.flight = null; this.moveTo(point); if (done) done(); }
      };
      this.flight = requestAnimationFrame(step);
    }

    cancelFlight() {
      if (this.flight) { cancelAnimationFrame(this.flight); this.flight = null; }
    }

    takeOff() { return this.setPose('take-off'); }
    land() { return this.setPose('land'); }
    lookAt() {}
    lookNeutral() {}
    blink() {}
  }

  /** Frames as <g id="…"> groups in one SVG (or a PNG strip). */
  class SpriteAdapter extends BaseAdapter {
    constructor(manifest, assetText) {
      super(manifest);
      const [fw, fh] = manifest.frameSize;
      const px = manifest.pixelScale || 1;
      this._size = fh * px;
      this._anchors = {};
      for (const [k, v] of Object.entries(manifest.anchors)) this._anchors[k] = [v[0] * px, v[1] * px];
      this.element.classList.add('moth-sprite');
      this.element.style.width = `calc(${fw * px}px * var(--moth-scale, 1))`;
      this.element.style.height = `calc(${fh * px}px * var(--moth-scale, 1))`;

      const doc = new DOMParser().parseFromString(assetText, 'image/svg+xml');
      this.svg = document.importNode(doc.documentElement, true);
      this.svg.setAttribute('width', '100%');
      this.svg.setAttribute('height', '100%');
      this.svg.removeAttribute('id');
      this.element.insertBefore(this.svg, this.hit);
      this.frames = {};
      for (const g of this.svg.querySelectorAll(':scope > g[id]')) {
        this.frames[g.id] = g;
        g.style.display = 'none';
      }
      this.cycle = null;
      this.current = null;
      this.setPose('perch-idle');
    }

    showFrame(name) {
      if (this.current) this.current.style.display = 'none';
      const g = this.frames[name];
      if (g) { g.style.display = ''; this.current = g; }
    }

    setPose(name, options = {}) {
      const spec = this.manifest.poses[name] || this.manifest.poses['perch-idle'];
      clearInterval(this.cycle);
      this.cycle = null;
      this.pose = name;
      const frames = spec.frames;
      this.showFrame(frames[0]);
      if (frames.length > 1 && spec.fps && !reduceMotion()) {
        let i = 0;
        const loop = name === 'fly';
        return new Promise((resolve) => {
          this.cycle = setInterval(() => {
            i += 1;
            if (!loop && i >= frames.length) {
              clearInterval(this.cycle); this.cycle = null; resolve(); return;
            }
            this.showFrame(frames[i % frames.length]);
          }, 1000 / spec.fps);
          if (loop) resolve();
        });
      }
      return Promise.resolve();
    }

    blink() {
      if (this.pose !== 'perch-idle' && this.pose !== 'perch-reading') return;
      const back = this.pose;
      this.showFrame(this.manifest.poses.doze.frames[0]);
      setTimeout(() => { if (this.pose === back) this.showFrame(this.manifest.poses[back].frames[0]); }, 120);
    }
  }

  /** Layered SVG parts driven by manifest transforms. */
  class RigAdapter extends BaseAdapter {
    constructor(manifest, assetText) {
      super(manifest);
      const [, , vw, vh] = manifest.viewBox;
      const s = manifest.size / vh;
      this._size = manifest.size;
      this._anchors = {};
      for (const [k, v] of Object.entries(manifest.anchors)) this._anchors[k] = [v[0] * s, v[1] * s];
      this.unit = s;
      this.element.classList.add('moth-rig');
      this.element.style.width = `calc(${vw * s}px * var(--moth-scale, 1))`;
      this.element.style.height = `calc(${vh * s}px * var(--moth-scale, 1))`;
      const doc = new DOMParser().parseFromString(assetText, 'image/svg+xml');
      this.svg = document.importNode(doc.documentElement, true);
      this.svg.setAttribute('width', '100%');
      this.svg.setAttribute('height', '100%');
      this.element.insertBefore(this.svg, this.hit);
      this.parts = {};
      for (const [id, spec] of Object.entries(manifest.parts)) {
        const g = this.svg.querySelector(`#${CSS.escape(id)}`);
        if (g) this.parts[id] = { el: g, pivot: spec.pivot, hidden: !!spec.hidden };
      }
      this.variants = new Set();
      this.setPose('perch-idle');
    }

    setVariants(list) { this.variants = new Set(list || []); this.setPose(this.pose || 'perch-idle'); }

    setPose(name, options = {}) {
      this.pose = name;
      const changes = {};
      for (const [id, part] of Object.entries(this.parts)) changes[id] = { visible: !part.hidden };
      const apply = (table) => {
        for (const [id, spec] of Object.entries(table || {})) Object.assign(changes[id] = changes[id] || {}, spec);
      };
      for (const v of this.variants) apply((this.manifest.variants || {})[v]);
      apply(this.manifest.poses[name]);
      const ms = options.transition ?? (reduceMotion() ? 0 : 160);
      for (const [id, c] of Object.entries(changes)) {
        const part = this.parts[id];
        if (!part) continue;
        const [px, py] = part.pivot;
        let t = '';
        if (c.rotate !== undefined || c.scale !== undefined || c.translate) {
          t = `translate(${px}px, ${py}px)`;
          if (c.rotate !== undefined) t += ` rotate(${c.rotate}deg)`;
          if (c.scale !== undefined) t += ` scale(${c.scale})`;
          t += ` translate(${-px}px, ${-py}px)`;
          if (c.translate) t = `translate(${c.translate[0]}px, ${c.translate[1]}px) ` + t;
        }
        part.el.style.transition = ms ? `transform ${ms}ms ease, opacity ${ms}ms ease` : 'none';
        part.el.style.transform = t;
        part.el.style.opacity = c.opacity !== undefined ? String(c.opacity) : '';
        part.el.style.display = c.visible === false ? 'none' : '';
      }
      return new Promise((resolve) => setTimeout(resolve, ms));
    }

    lookAt(x, y) {
      const range = this.manifest.pupilRange || 1;
      const rect = this.element.getBoundingClientRect();
      const cx = rect.left + window.scrollX + rect.width / 2, cy = rect.top + window.scrollY + rect.height / 3;
      const dx = Math.max(-1, Math.min(1, (x - cx) / 200)), dy = Math.max(-1, Math.min(1, (y - cy) / 200));
      for (const id of this.manifest.pupils || []) {
        const el = this.svg.querySelector(`#${CSS.escape(id)}`);
        if (el) el.style.transform = `translate(${dx * range}px, ${dy * range}px)`;
      }
    }

    lookNeutral() {
      for (const id of this.manifest.pupils || []) {
        const el = this.svg.querySelector(`#${CSS.escape(id)}`);
        if (el) el.style.transform = '';
      }
    }

    blink() {
      const lids = this.parts.lids, eyes = this.parts.eyes;
      if (!lids || !eyes) return;
      lids.el.style.display = ''; eyes.el.style.display = 'none';
      setTimeout(() => { lids.el.style.display = 'none'; eyes.el.style.display = ''; }, 120);
    }
  }

  window.MothAdapters = {
    create(manifest, assetText) {
      if (manifest.type === 'svg-rig') return new RigAdapter(manifest, assetText);
      if (manifest.type === 'spritesheet') return new SpriteAdapter(manifest, assetText);
      throw new Error(`unsupported moth pack type ${manifest.type}`);
    },
  };
})();
