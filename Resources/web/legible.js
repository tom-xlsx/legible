/* Legible render pipeline. Runs inside the WKWebView; talks to Swift via
   window.webkit.messageHandlers.legible. Swift calls window.Legible.* */
(() => {
  'use strict';

  const post = (msg) => {
    try { window.webkit.messageHandlers.legible.postMessage(msg); } catch (_) { /* not in the app */ }
  };
  window.addEventListener('error', (e) => post({ type: 'error', message: `${e.message} (${e.filename}:${e.lineno})` }));
  window.addEventListener('unhandledrejection', (e) => post({ type: 'error', message: `Unhandled rejection: ${e.reason}` }));

  const root = document.getElementById('doc');
  const themeStyle = document.getElementById('theme');
  const overrideStyle = document.getElementById('overrides');
  /** Raw source of every code block in the current render, for copy buttons. */
  let rawCode = [];

  // ---- markdown-it (see legible-core.js) --------------------------------

  const core = window.LegibleCore.create({ html: true });

  // ---- Sanitising --------------------------------------------------------
  // The safe subset real READMEs use. Anything that can run code, phone home,
  // take input or cover the page is dropped: script, iframe, object, embed,
  // form, button, textarea, select, style, link, meta, base, svg, math, video,
  // audio, and every on* attribute and style attribute.

  const PURIFY_OPTIONS = {
    ALLOWED_TAGS: [
      'a', 'abbr', 'b', 'blockquote', 'br', 'caption', 'code', 'col', 'colgroup',
      'dd', 'del', 'details', 'div', 'dl', 'dt', 'em', 'figcaption', 'figure',
      'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'hr', 'i', 'img', 'input', 'ins', 'kbd',
      'li', 'mark', 'ol', 'p', 'picture', 'pre', 'q', 's', 'samp', 'section',
      'small', 'source', 'span', 'strike', 'strong', 'sub', 'summary', 'sup',
      'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'tt', 'u', 'ul',
      'var', 'wbr',
    ],
    ALLOWED_ATTR: [
      'align', 'alt', 'checked', 'class', 'colspan', 'dir', 'disabled', 'height',
      'href', 'id', 'lang', 'loading', 'media', 'name', 'open', 'rowspan',
      'sizes', 'src', 'srcset', 'start', 'title', 'type', 'valign', 'width',
    ],
    ALLOW_DATA_ATTR: true,
    ALLOW_ARIA_ATTR: false,
    KEEP_CONTENT: true,
    // Dropped elements normally leave their text behind; these should vanish wholesale.
    FORBID_CONTENTS: ['script', 'style', 'iframe', 'object', 'embed', 'form', 'button', 'textarea', 'select',
      'svg', 'math', 'video', 'audio', 'template', 'noscript'],
  };

  // The only <input> allowed is the disabled checkbox task lists produce.
  window.DOMPurify.addHook('uponSanitizeElement', (node, data) => {
    if (data.tagName !== 'input') return;
    if (node.getAttribute('type') !== 'checkbox') { node.parentNode?.removeChild(node); return; }
    node.setAttribute('disabled', '');
  });

  // ---- Helpers -----------------------------------------------------------

  function assignHeadingIds() {
    const seen = new Map();
    const headings = [];
    for (const h of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
      let id = h.id || window.LegibleCore.slugify(h.textContent) || 'section';
      const n = seen.get(id) || 0;
      seen.set(id, n + 1);
      if (n > 0) id = `${id}-${n}`;
      h.id = id;
      headings.push({ level: Number(h.tagName[1]), text: h.textContent.trim(), id });
    }
    return headings;
  }

  const isRelative = (u) => u && !/^[a-z][a-z0-9+.-]*:/i.test(u) && !u.startsWith('#') && !u.startsWith('//');

  function resolveRelativeUrls(docBase) {
    if (!docBase) return;
    const resolve = (u) => { try { return new URL(u, docBase).href; } catch (_) { return u; } };
    for (const el of root.querySelectorAll('img[src], source[src]')) {
      const src = el.getAttribute('src');
      if (isRelative(src)) el.setAttribute('src', resolve(src));
    }
    for (const el of root.querySelectorAll('img[srcset], source[srcset]')) {
      const srcset = el.getAttribute('srcset').split(',').map((part) => {
        const [url, ...rest] = part.trim().split(/\s+/);
        return [isRelative(url) ? resolve(url) : url, ...rest].join(' ');
      }).join(', ');
      el.setAttribute('srcset', srcset);
    }
    for (const a of root.querySelectorAll('a[href]')) {
      const href = a.getAttribute('href');
      if (isRelative(href)) a.setAttribute('href', resolve(href));
    }
  }

  /** Scrolls without reporting the movement to Swift as a user scroll. */
  let suppressScrollReports = false;
  function programmaticScroll(fn) {
    suppressScrollReports = true;
    fn();
    requestAnimationFrame(() => requestAnimationFrame(() => { suppressScrollReports = false; }));
  }

  function scrollAnchor() {
    for (const el of root.querySelectorAll('[data-line]')) {
      const r = el.getBoundingClientRect();
      if (r.bottom > 0) return { line: Number(el.dataset.line), offset: r.top };
    }
    return null;
  }

  function restoreScroll(anchor) {
    let best = null;
    for (const el of root.querySelectorAll('[data-line]')) {
      const line = Number(el.dataset.line);
      if (line <= anchor.line && (!best || line > Number(best.dataset.line))) best = el;
    }
    if (!best) return;
    const top = best.getBoundingClientRect().top;
    programmaticScroll(() => window.scrollTo({ top: window.scrollY + top - anchor.offset, behavior: 'instant' }));
  }

  /** A missing or blocked image becomes its alt text, instead of WebKit's "?" box. */
  function markMissing(img) {
    const span = document.createElement('span');
    span.className = 'image-missing';
    const align = img.getAttribute('align');
    if (align) span.setAttribute('data-align', align);
    span.title = img.getAttribute('src') || '';
    span.textContent = img.getAttribute('alt') || 'Missing image';
    img.replaceWith(span);
  }

  function whenImagesSettled() {
    const pending = [];
    for (const img of root.querySelectorAll('img')) {
      if (img.complete) {
        if (img.naturalWidth === 0) markMissing(img);
        continue;
      }
      pending.push(new Promise((resolve) => {
        img.onload = resolve;
        img.onerror = () => { markMissing(img); resolve(); };
      }));
    }
    return Promise.all(pending);
  }

  function wordCount() {
    if (root.querySelector('.empty-state')) return 0;
    const clone = root.cloneNode(true);
    for (const el of clone.querySelectorAll('.ornament, .copy')) el.remove();
    return clone.textContent.split(/\s+/).filter(Boolean).length;
  }

  // ---- Copy buttons ------------------------------------------------------

  const state = { copyMessages: ['Copied.'], emptyStates: ['This file is empty.'], garnish: null };

  function addCopyButtons() {
    for (const block of root.querySelectorAll('.code-block[data-code]')) {
      const index = Number(block.dataset.code);
      if (!(index in rawCode)) continue;
      const button = document.createElement('button');
      button.type = 'button';
      button.className = 'copy';
      button.textContent = 'Copy';
      const lang = block.dataset.lang;
      button.setAttribute('aria-label', lang ? `Copy ${lang} code` : 'Copy code');
      button.addEventListener('click', () => {
        post({ type: 'copy', text: copyText(index) });
        if (window.LegibleGarnish) window.LegibleGarnish.copied();
        const message = state.copyMessages[Math.floor(Math.random() * state.copyMessages.length)];
        button.textContent = message;
        button.classList.add('copied');
        clearTimeout(button._timer);
        button._timer = setTimeout(() => {
          button.textContent = 'Copy';
          button.classList.remove('copied');
        }, 1400);
      });
      block.appendChild(button);
    }
  }

  /** The raw fence content minus the single newline that terminates its last line. */
  function copyText(index) {
    const raw = rawCode[index] || '';
    return raw.endsWith('\n') ? raw.slice(0, -1) : raw;
  }

  // ---- Find ----------------------------------------------------------------

  function textMatches(query) {
    const needle = query.toLowerCase();
    const matches = [];
    if (!needle) return matches;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node;
    while ((node = walker.nextNode())) {
      const text = node.nodeValue.toLowerCase();
      let at = text.indexOf(needle);
      while (at !== -1) {
        matches.push({ node, offset: at });
        at = text.indexOf(needle, at + needle.length);
      }
    }
    return matches;
  }

  /** {index (1-based, 0 if none selected), total} for the current selection. */
  function findStatus(query) {
    const matches = textMatches(query);
    const sel = window.getSelection();
    let index = 0;
    if (matches.length && sel && sel.rangeCount) {
      const range = sel.getRangeAt(0);
      for (let i = 0; i < matches.length; i++) {
        const m = matches[i];
        const probe = document.createRange();
        probe.setStart(m.node, m.offset);
        probe.setEnd(m.node, m.offset);
        if (probe.compareBoundaryPoints(Range.START_TO_START, range) === 0) { index = i + 1; break; }
        if (probe.compareBoundaryPoints(Range.START_TO_START, range) > 0) break;
      }
    }
    return { index, total: matches.length };
  }

  // ---- Self-test -----------------------------------------------------------
  // Assertions about the rendered kitchen sink; returns a list of failures.

  function selfTest() {
    const failures = [];
    const assert = (ok, message) => { if (!ok) failures.push(message); };

    assert(document.title === 'Legible', `document.title was changed to "${document.title}"`);
    const forbidden = 'script, iframe, object, embed, form, button:not(.copy), textarea, select, style, link, meta, base, svg, math, video, audio, input:not([type=checkbox])';
    assert(root.querySelectorAll(forbidden).length === 0, `forbidden elements survived: ${[...root.querySelectorAll(forbidden)].map((e) => e.tagName).join(', ')}`);
    for (const el of root.querySelectorAll('*')) {
      for (const attr of el.attributes) {
        assert(!/^on/i.test(attr.name), `event handler attribute survived: <${el.tagName.toLowerCase()} ${attr.name}>`);
        assert(attr.name !== 'style', `style attribute survived on <${el.tagName.toLowerCase()}>`);
      }
    }
    assert(root.querySelectorAll('a[href^="javascript:" i]').length === 0, 'javascript: link survived');
    for (const img of root.querySelectorAll('img')) {
      const src = img.getAttribute('src') || '';
      if (/^(https?|file):/i.test(src) || src.includes('not-a-token')) {
        assert(!(img.complete && img.naturalWidth > 0), `image loaded from ${src}`);
      }
    }
    const marker = [...root.querySelectorAll('p')].find((p) => p.textContent.startsWith('End of the malicious section'));
    assert(marker && marker.offsetParent !== null, 'end-of-section marker is not visible');
    assert(getComputedStyle(document.body).display !== 'none', 'body was hidden');
    assert(root.querySelectorAll('input[type=checkbox]:not([disabled])').length === 0, 'an enabled checkbox survived');
    assert(!root.textContent.includes('Submit'), 'a stripped form left its button text behind');

    const local = [...root.querySelectorAll('img[src^="legible-doc:"]')].filter((i) => i.getAttribute('src').endsWith('gradient.png'));
    assert(local.length > 0 && local.every((i) => i.naturalWidth > 0), 'relative image gradient.png did not load');

    const blocks = [...root.querySelectorAll('.code-block')];
    assert(blocks.length >= 10, `expected at least 10 code blocks, found ${blocks.length}`);
    assert(blocks.every((b) => b.querySelector('button.copy')), 'a code block has no copy button');
    const plain = blocks.find((b) => b.textContent.includes('A fence with no language'));
    assert(plain && !plain.hasAttribute('data-lang'), 'unlabelled fence has a language label');
    const text = plain ? copyText(Number(plain.dataset.code)) : '';
    assert(text.endsWith('whitespace.   '), 'copy text lost trailing whitespace or kept the final newline');
    assert(text.startsWith('A fence with no language. Copy should return exactly this,'), 'copy text does not start with the raw source');
    const html = blocks.find((b) => b.dataset.lang === 'html');
    assert(html && html.textContent.includes('<script>alert("this is text, not a script")</script>'), 'html code block did not show its source as text');
    assert(root.querySelector('.code-block[data-lang="mermaid"]'), 'mermaid fence is not a plain code block');

    if (!state.garnish) {
      assert(!document.querySelector('.moth, .moth-mark, .moth-evidence'), 'moth present while the garnish is held');
      assert(!root.querySelector('.ornament'), 'ornament present while the garnish is held');
    }
    const ids = [...root.querySelectorAll('h1, h2, h3, h4, h5, h6')].map((h) => h.id);
    assert(new Set(ids).size === ids.length, `duplicate heading ids: ${ids.join(', ')}`);
    assert(ids.includes('level-three') && ids.includes('level-three-1'), 'heading id de-duplication failed');
    assert(root.querySelectorAll('.alert').length === 3, `expected 3 alerts, found ${root.querySelectorAll('.alert').length}`);
    assert(root.querySelector('.alert-warning .alert-title')?.textContent === 'Warning', 'warning alert has no title');
    assert(!root.querySelector('.alert')?.textContent.includes('[!'), 'alert marker was not removed');
    assert([...root.querySelectorAll('blockquote')].some((q) => q.textContent.includes('Not an alert')), 'marker mid-line was treated as an alert');
    assert(root.querySelector('details.front-matter'), 'front matter block missing');
    assert(!root.textContent.includes('title: Kitchen Sink') || root.querySelector('.front-matter pre'), 'front matter leaked into the body');
    assert(root.querySelectorAll('.footnotes li').length === 2, 'footnotes missing');
    assert(root.querySelectorAll('.task-list-item').length === 3, 'task list items missing');

    return failures;
  }

  // ---- Focus mode (themes with "@focus true") ------------------------------
  // The block crossing the reading line (about a third of the way down) is
  // shown at full strength; everything else takes --focus-dim.

  let focusFrame = 0;
  function updateFocus() {
    if (!document.documentElement.classList.contains('focus-mode')) return;
    const line = window.innerHeight * 0.38;
    let best = null, bestDistance = Infinity;
    for (const el of root.children) {
      const r = el.getBoundingClientRect();
      if (r.height === 0) continue;
      const distance = r.top <= line && r.bottom >= line ? 0 : Math.min(Math.abs(r.top - line), Math.abs(r.bottom - line));
      if (distance < bestDistance) { best = el; bestDistance = distance; }
    }
    for (const el of root.querySelectorAll(':scope > .focused')) if (el !== best) el.classList.remove('focused');
    if (best) best.classList.add('focused');
  }
  window.addEventListener('scroll', () => {
    cancelAnimationFrame(focusFrame);
    focusFrame = requestAnimationFrame(updateFocus);
  }, { passive: true });
  window.addEventListener('resize', updateFocus);

  // ---- Scroll sync with the editor -----------------------------------------
  // Block elements carry data-line (their first source line). Positions
  // between two stamped blocks are interpolated.

  function lineElements() {
    // Footnote definitions render at the end regardless of where they were
    // written, so they are left out; everything else is in source order.
    return [...root.querySelectorAll('[data-line]')]
      .filter((el) => !el.closest('.footnotes'))
      .map((el) => ({ el, line: Number(el.dataset.line), top: el.getBoundingClientRect().top + window.scrollY }))
      .filter((e) => Number.isFinite(e.line))
      .sort((a, b) => a.top - b.top || a.line - b.line);
  }

  /** Fractional source line at the top of the viewport. */
  function topLine() {
    const items = lineElements();
    if (!items.length) return 0;
    const y = window.scrollY;
    let prev = null;
    for (const item of items) {
      if (item.top > y) {
        if (!prev) return Math.max(0, item.line - 1);
        const span = item.top - prev.top;
        const ratio = span > 0 ? (y - prev.top) / span : 0;
        return prev.line + ratio * (item.line - prev.line);
      }
      prev = item;
    }
    const last = items[items.length - 1];
    const tail = Math.max(1, last.el.getBoundingClientRect().height);
    return last.line + Math.min(1, (y - last.top) / tail);
  }

  function scrollToLine(line) {
    const items = lineElements();
    if (!items.length) return;
    let y;
    let prev = null;
    for (const item of items) {
      if (item.line > line) {
        if (!prev) { y = 0; break; }
        const ratio = item.line > prev.line ? (line - prev.line) / (item.line - prev.line) : 0;
        y = prev.top + ratio * (item.top - prev.top);
        break;
      }
      prev = item;
    }
    if (y === undefined) {
      const last = items[items.length - 1];
      y = last.top + (line - last.line) * last.el.getBoundingClientRect().height;
    }
    programmaticScroll(() => window.scrollTo({ top: Math.max(0, y - 16), behavior: 'instant' }));
  }

  /** Id of the heading being read: the last one at or above the reading line. */
  function currentHeading() {
    const line = window.innerHeight * 0.3;
    let current = null;
    for (const h of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
      if (h.getBoundingClientRect().top <= line) current = h.id; else break;
    }
    if (!current) {
      const first = root.querySelector('h1, h2, h3, h4, h5, h6');
      current = first ? first.id : null;
    }
    return current;
  }

  function scrollToHeading(id) {
    const el = document.getElementById(id);
    if (el) el.scrollIntoView({ block: 'start' });
  }

  let scrollFrame = 0;
  function reportScroll() {
    cancelAnimationFrame(scrollFrame);
    scrollFrame = requestAnimationFrame(() => post({ type: 'scroll', line: topLine(), heading: currentHeading(),
      atEnd: window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2 }));
  }
  window.addEventListener('scroll', () => {
    if (suppressScrollReports) return;
    reportScroll();
  }, { passive: true });

  // ---- Public API (called from Swift) ------------------------------------

  const Legible = {
    render({ markdown, docBase, preserveScroll, showEmptyState = true }) {
      const anchor = preserveScroll ? scrollAnchor() : null;
      const rendered = core.render(markdown || '');
      rawCode = rendered.code;

      root.innerHTML = window.DOMPurify.sanitize(rendered.html, PURIFY_OPTIONS);
      if (showEmptyState && !root.textContent.trim() && !root.querySelector('img')) {
        const empty = document.createElement('p');
        empty.className = 'empty-state';
        empty.textContent = state.emptyStates[Math.floor(Math.random() * state.emptyStates.length)];
        root.appendChild(empty);
      }
      const headings = assignHeadingIds();
      resolveRelativeUrls(docBase);
      addCopyButtons();
      if (window.LegibleGarnish) window.LegibleGarnish.afterRender();

      if (anchor) restoreScroll(anchor);
      else if (!preserveScroll) programmaticScroll(() => window.scrollTo({ top: 0, behavior: 'instant' }));
      updateFocus();

      whenImagesSettled().then(() => {
        if (window.LegibleGarnish) window.LegibleGarnish.afterRender();   // images may have moved things
        post({ type: 'rendered', words: wordCount(), headings, codeBlocks: rawCode.length });
      });
    },

    setTheme(css) {
      themeStyle.textContent = css || '';
      const focus = /@focus\s+true/i.test(css || '');
      document.documentElement.classList.toggle('focus-mode', focus);
      if (focus) updateFocus();
    },

    setOverrides(css) {
      overrideStyle.textContent = css || '';
    },

    codeAt(index) {
      return rawCode[index];
    },

    configure(options) {
      const garnish = options.garnish || {};
      state.copyMessages = Array.isArray(garnish.copyMessages) && garnish.copyMessages.length ? garnish.copyMessages : ['Copied.'];
      state.emptyStates = Array.isArray(garnish.emptyStates) && garnish.emptyStates.length ? garnish.emptyStates : ['This file is empty.'];
      const empty = root.querySelector('.empty-state');
      if (empty) empty.textContent = state.emptyStates[0];
      state.garnish = (garnish.moth && garnish.moth.enabled) || garnish.ornament ? garnish : null;
      if (window.LegibleGarnish) window.LegibleGarnish.configure(garnish);
    },

    findStatus,
    selfTest,
    scrollToLine,
    scrollToHeading,
    topLine,
    currentHeading,
  };

  window.Legible = Legible;

  // In-page anchors scroll; everything else is decided by Swift's navigation policy.
  root.addEventListener('click', (e) => {
    const a = e.target.closest('a[href]');
    if (!a) return;
    const href = a.getAttribute('href');
    if (href.startsWith('#')) {
      e.preventDefault();
      const target = document.getElementById(decodeURIComponent(href.slice(1)));
      if (target) target.scrollIntoView({ block: 'start' });
    }
  });

  post({ type: 'ready' });
})();
