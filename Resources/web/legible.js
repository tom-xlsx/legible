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
  const escapeHtml = window.markdownit().utils.escapeHtml;

  /** Raw source of every code block in the current render, for copy buttons. */
  const rawCode = [];

  // ---- markdown-it -----------------------------------------------------

  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: false })
    .use(window.markdownitFootnote)
    .use(window.markdownitTaskLists, { enabled: false, label: true });

  // Stamp block tokens with their source line so scroll position can be
  // preserved across re-renders and synced with the editor.
  md.core.ruler.push('source_lines', (state) => {
    const offset = (state.env && state.env.lineOffset) || 0;
    for (const t of state.tokens) {
      if (!t.map || t.nesting < 0 || t.type === 'inline') continue;
      if (t.type === 'fence' || t.type === 'code_block' || t.type === 'html_block') continue;
      t.attrSet('data-line', String(t.map[0] + offset));
    }
  });

  function renderCode(content, lang, map, env) {
    const offset = (env && env.lineOffset) || 0;
    let body;
    if (lang && window.hljs.getLanguage(lang)) {
      body = window.hljs.highlight(content, { language: lang, ignoreIllegals: true }).value;
    } else {
      body = escapeHtml(content);
    }
    const index = rawCode.push(content) - 1;
    const line = map ? ` data-line="${map[0] + offset}"` : '';
    const langAttr = lang ? ` data-lang="${escapeHtml(lang)}"` : '';
    const cls = lang ? ` language-${escapeHtml(lang)}` : '';
    return `<div class="code-block"${line} data-code="${index}"${langAttr}>` +
      `<pre><code class="hljs${cls}">${body}</code></pre></div>\n`;
  }

  md.renderer.rules.fence = (tokens, idx, _opts, env) => {
    const t = tokens[idx];
    const info = t.info ? md.utils.unescapeAll(t.info).trim() : '';
    const lang = info.split(/\s+/)[0] || '';
    return renderCode(t.content, lang, t.map, env);
  };
  md.renderer.rules.code_block = (tokens, idx, _opts, env) =>
    renderCode(tokens[idx].content, '', tokens[idx].map, env);

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
  };

  // The only <input> allowed is the disabled checkbox task lists produce.
  window.DOMPurify.addHook('uponSanitizeElement', (node, data) => {
    if (data.tagName !== 'input') return;
    if (node.getAttribute('type') !== 'checkbox') { node.parentNode?.removeChild(node); return; }
    node.setAttribute('disabled', '');
  });

  // ---- Helpers -----------------------------------------------------------

  function splitFrontMatter(text) {
    const m = /^---[ \t]*\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/.exec(text);
    if (!m) return { frontMatter: null, body: text, lineOffset: 0 };
    return { frontMatter: m[1], body: text.slice(m[0].length), lineOffset: m[0].split('\n').length - 1 };
  }

  function slugify(text) {
    return text.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s-]/gu, '')
      .replace(/\s+/g, '-');
  }

  function assignHeadingIds() {
    const seen = new Map();
    const headings = [];
    for (const h of root.querySelectorAll('h1, h2, h3, h4, h5, h6')) {
      let id = h.id || slugify(h.textContent) || 'section';
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
    window.scrollTo({ top: window.scrollY + top - anchor.offset, behavior: 'instant' });
  }

  function whenImagesSettled() {
    const pending = [...root.querySelectorAll('img')]
      .filter((img) => !img.complete)
      .map((img) => new Promise((resolve) => { img.onload = img.onerror = resolve; }));
    return Promise.all(pending);
  }

  function wordCount() {
    return root.innerText.split(/\s+/).filter(Boolean).length;
  }

  // ---- Public API (called from Swift) ------------------------------------

  const Legible = {
    render({ markdown, docBase, preserveScroll }) {
      const anchor = preserveScroll ? scrollAnchor() : null;
      rawCode.length = 0;

      const { frontMatter, body, lineOffset } = splitFrontMatter(markdown || '');
      let html = md.render(body, { lineOffset });
      if (frontMatter !== null) {
        html = `<details class="front-matter"><summary>Front matter</summary>` +
          `<pre>${escapeHtml(frontMatter)}</pre></details>\n` + html;
      }

      root.innerHTML = window.DOMPurify.sanitize(html, PURIFY_OPTIONS);
      const headings = assignHeadingIds();
      resolveRelativeUrls(docBase);

      if (anchor) restoreScroll(anchor);
      else if (!preserveScroll) window.scrollTo({ top: 0, behavior: 'instant' });

      whenImagesSettled().then(() => {
        post({ type: 'rendered', words: wordCount(), headings, codeBlocks: rawCode.length });
      });
    },

    setTheme(css) {
      themeStyle.textContent = css || '';
    },

    codeAt(index) {
      return rawCode[index];
    },
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
