/* Garnish: the end-of-document ornament, and the hand-off to the moth
   (moth/moth.js). Everything here is inert until Legible.configure({ garnish })
   switches a feature on. */
(() => {
  'use strict';

  const root = document.getElementById('doc');

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
      ornamentEnabled = !!o.ornament;
      placeOrnament();
      if (window.LegibleMoth) window.LegibleMoth.configure(o.moth || { enabled: false });
    },
    afterRender() {
      placeOrnament();
      if (window.LegibleMoth) window.LegibleMoth.afterRender();
    },
    copied() {
      if (window.LegibleMoth) window.LegibleMoth.event('copy');
    },
  };
})();
