/* Garnish: the moth and the ornament. Everything here is inert until
   Legible.configure({ garnish: {...} }) switches a feature on. */
(() => {
  'use strict';

  const root = document.getElementById('doc');
  const reduceMotion = () => window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- Moth ------------------------------------------------------------------
  // Drawn with the theme's variables. Fixed to a corner, click-through, and
  // hidden whenever it would overlap the text column.

  const MOTH_SVG = `
<svg viewBox="0 0 120 120" width="84" height="84" aria-hidden="true" focusable="false">
  <g class="moth-wings">
    <path class="moth-wing" d="M57 60 C42 34, 10 30, 15 58 C19 80, 42 82, 57 66 Z"/>
    <path class="moth-wing" d="M63 60 C78 34, 110 30, 105 58 C101 80, 78 82, 63 66 Z"/>
    <path class="moth-wing" d="M56 70 C44 82, 26 94, 30 74 C33 66, 46 66, 56 70 Z"/>
    <path class="moth-wing" d="M64 70 C76 82, 94 94, 90 74 C87 66, 74 66, 64 70 Z"/>
  </g>
  <ellipse class="moth-body" cx="60" cy="68" rx="8" ry="20"/>
  <g class="moth-head">
    <path class="moth-antenna" d="M55 34 C50 24, 42 20, 37 15"/>
    <path class="moth-antenna" d="M65 34 C70 24, 78 20, 83 15"/>
    <circle class="moth-face" cx="60" cy="42" r="11"/>
    <g class="moth-eyes">
      <circle class="moth-eye" cx="54" cy="43" r="4.2"/>
      <circle class="moth-eye" cx="66" cy="43" r="4.2"/>
      <circle class="moth-pupil" cx="54" cy="43" r="1.9"/>
      <circle class="moth-pupil" cx="66" cy="43" r="1.9"/>
    </g>
    <g class="moth-lids">
      <path d="M50 43.5 C52 45.5, 56 45.5, 58 43.5"/>
      <path d="M62 43.5 C64 45.5, 68 45.5, 70 43.5"/>
    </g>
    <g class="moth-glasses">
      <circle cx="54" cy="43" r="6.2"/>
      <circle cx="66" cy="43" r="6.2"/>
      <path d="M60.2 43 h-0.4"/>
      <path d="M47.8 42 l-4 -1.5"/>
      <path d="M72.2 42 l4 -1.5"/>
    </g>
  </g>
  <text class="moth-zzz" x="86" y="30">z</text>
  <text class="moth-zzz moth-zzz-2" x="94" y="20">z</text>
  <g class="moth-book moth-book-open">
    <path d="M40 98 L60 102 L80 98 L80 84 L60 88 L40 84 Z"/>
    <path d="M60 88 v14"/>
    <path d="M45 90 l10 2 M45 94 l10 2 M65 92 l10 -2 M65 96 l10 -2" class="moth-lines"/>
  </g>
  <g class="moth-book moth-book-closed">
    <rect x="44" y="86" width="32" height="14" rx="2"/>
    <path d="M48 86 v14" class="moth-lines"/>
  </g>
</svg>`;

  const moth = {
    el: null,
    enabled: false,
    idleTimer: null,
    lastActivity: Date.now(),
    driftFrame: 0,

    enable() {
      if (this.el) { this.el.hidden = false; this.layout(); return; }
      const el = document.createElement('div');
      el.id = 'moth';
      el.innerHTML = MOTH_SVG;
      el.setAttribute('aria-hidden', 'true');
      document.body.appendChild(el);
      this.el = el;
      this.enabled = true;
      this.wake();
      this.layout();
      this.idleTimer = setInterval(() => {
        if (Date.now() - this.lastActivity > 30000) this.el.classList.add('dozing');
      }, 5000);
    },

    disable() {
      if (!this.el) return;
      this.el.remove();
      this.el = null;
      this.enabled = false;
      clearInterval(this.idleTimer);
    },

    wake() {
      this.lastActivity = Date.now();
      if (this.el) this.el.classList.remove('dozing');
    },

    /** Hide when the text column reaches into the corner the moth sits in. */
    layout() {
      if (!this.el) return;
      const column = root.getBoundingClientRect();
      const clear = window.innerWidth - column.right >= 110 && window.innerHeight > 360;
      this.el.classList.toggle('moth-tucked', !clear);
      this.follow();
    },

    /** Eyes follow the scroll position; the book closes at the end. */
    follow() {
      if (!this.el) return;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      const fraction = max > 0 ? Math.min(1, Math.max(0, window.scrollY / max)) : 0;
      const dy = (fraction - 0.5) * 3.2;
      for (const pupil of this.el.querySelectorAll('.moth-pupil')) pupil.setAttribute('cy', String(43 + dy));
      const atEnd = max <= 0 || window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
      this.el.classList.toggle('book-closed', atEnd);
      this.drift();
    },

    nod() {
      if (!this.el) return;
      this.wake();
      this.el.classList.remove('nodding');
      void this.el.offsetWidth;
      this.el.classList.add('nodding');
      setTimeout(() => this.el && this.el.classList.remove('nodding'), reduceMotion() ? 600 : 900);
    },

    /** In dark themes, lean a little toward the brightest thing on screen. */
    drift() {
      if (!this.el) return;
      const bg = getComputedStyle(document.documentElement).getPropertyValue('--bg').trim();
      const dark = luminance(bg) < 0.4;
      let shift = 0;
      if (dark) {
        let best = null, bestL = luminance(bg) + 0.08;
        for (const el of root.querySelectorAll('.code-block, blockquote, table, img, .front-matter')) {
          const r = el.getBoundingClientRect();
          if (r.bottom < 0 || r.top > window.innerHeight || r.width === 0) continue;
          const l = el.tagName === 'IMG' ? 0.9 : luminance(getComputedStyle(el).backgroundColor);
          if (l > bestL) { bestL = l; best = r; }
        }
        if (best) {
          const centre = best.left + best.width / 2;
          const home = window.innerWidth - 60;
          shift = Math.max(-70, Math.min(0, (centre - home) * 0.15));
        }
      }
      this.el.style.setProperty('--moth-drift', `${shift.toFixed(1)}px`);
    },
  };

  function luminance(css) {
    const m = /rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?\)/.exec(css) ||
      (/^#([0-9a-f]{6})$/i.test(css) ? ['', ...css.slice(1).match(/../g).map((h) => parseInt(h, 16))] : null);
    if (!m) return 1;
    if (m[4] !== undefined && Number(m[4]) === 0) return -1;
    const lin = (c) => { c /= 255; return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; };
    return 0.2126 * lin(+m[1]) + 0.7152 * lin(+m[2]) + 0.0722 * lin(+m[3]);
  }

  for (const type of ['mousemove', 'keydown', 'pointerdown', 'wheel']) {
    window.addEventListener(type, () => moth.wake(), { passive: true });
  }
  let settleTimer = 0;
  window.addEventListener('scroll', () => {
    moth.wake();
    cancelAnimationFrame(moth.driftFrame);
    moth.driftFrame = requestAnimationFrame(() => moth.follow());
    clearTimeout(settleTimer);
    settleTimer = setTimeout(() => moth.follow(), 250);   // once layout has settled
  }, { passive: true });
  window.addEventListener('resize', () => moth.layout());

  // ---- Ornament ----------------------------------------------------------------

  const ORNAMENT_SVG = `
<svg viewBox="0 0 64 24" width="64" height="24" aria-hidden="true" focusable="false">
  <circle cx="32" cy="12" r="9.5"/>
  <circle cx="32" cy="12" r="5.5"/>
  <path d="M10 3 v7 M14 3 v7 M12 3 v18 M10 10 c0 2, 4 2, 4 0"/>
  <path d="M52 3 c-3 0, -4 5, -4 8 c0 2, 2 3, 4 3 v7 M52 3 v11"/>
</svg>`;

  let ornamentEnabled = false;
  function placeOrnament() {
    const existing = root.querySelector('.ornament');
    if (existing) existing.remove();
    if (!ornamentEnabled || !root.textContent.trim()) return;
    const el = document.createElement('div');
    el.className = 'ornament';
    el.innerHTML = ORNAMENT_SVG;
    el.setAttribute('aria-hidden', 'true');
    const footnotes = root.querySelector('.footnotes');
    if (footnotes) root.insertBefore(el, footnotes.previousElementSibling && footnotes.previousElementSibling.classList.contains('footnotes-sep') ? footnotes.previousElementSibling : footnotes);
    else root.appendChild(el);
  }

  // ---- Public ------------------------------------------------------------------

  window.LegibleGarnish = {
    configure(options) {
      const o = options || {};
      if (o.mascot) moth.enable(); else moth.disable();
      ornamentEnabled = !!o.ornament;
      placeOrnament();
    },
    afterRender() {
      placeOrnament();
      moth.layout();
    },
    copied() {
      moth.nod();
    },
  };
})();
