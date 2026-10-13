/* Legible's Markdown-to-HTML core. No DOM: it runs in the WKWebView page and,
   unchanged, inside JavaScriptCore for the Quick Look extension. Everything
   that needs a document (sanitising, copy buttons, scrolling) lives in legible.js. */
(() => {
  'use strict';
  const g = globalThis;

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

  /** Plain text of an inline token, close to what the DOM's textContent would give. */
  function inlineText(token) {
    if (!token || !token.children) return token ? token.content : '';
    let out = '';
    for (const c of token.children) {
      if (c.type === 'text' || c.type === 'code_inline') out += c.content;
      else if (c.type === 'softbreak' || c.type === 'hardbreak') out += ' ';
      else if (c.type === 'html_inline') out += c.content.replace(/<[^>]*>/g, '');
      else if (c.children) out += inlineText(c);
    }
    return out;
  }

  /**
   * Builds a renderer. `html` is whether raw HTML in the source is parsed (the app
   * sanitises it afterwards; the Quick Look preview turns it off and shows it as text).
   */
  function create({ html = true } = {}) {
    const md = g.markdownit({ html, linkify: true, typographer: false, breaks: false })
      .use(g.markdownitFootnote)
      .use(g.markdownitTaskLists, { enabled: false, label: true });
    const escapeHtml = md.utils.escapeHtml;

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

    // Heading ids: slug of the text, de-duplicated with -1, -2… in document order.
    md.core.ruler.push('heading_ids', (state) => {
      const seen = new Map();
      const headings = state.env.headings || (state.env.headings = []);
      const tokens = state.tokens;
      for (let i = 0; i < tokens.length; i++) {
        const t = tokens[i];
        if (t.type !== 'heading_open') continue;
        const text = inlineText(tokens[i + 1]).trim();
        let id = t.attrGet('id') || slugify(text) || 'section';
        const n = seen.get(id) || 0;
        seen.set(id, n + 1);
        if (n > 0) id = `${id}-${n}`;
        t.attrSet('id', id);
        headings.push({ level: Number(t.tag[1]), text, id });
      }
    });

    function renderCode(content, lang, map, env) {
      const offset = (env && env.lineOffset) || 0;
      let body;
      if (lang && g.hljs.getLanguage(lang)) {
        body = g.hljs.highlight(content, { language: lang, ignoreIllegals: true }).value;
      } else {
        body = escapeHtml(content);
      }
      const code = env.code || (env.code = []);
      const index = code.push(content) - 1;
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

    /** Markdown → { html, code: [raw fence sources], headings: [{level, text, id}] }. */
    function render(markdown) {
      const { frontMatter, body, lineOffset } = splitFrontMatter(markdown || '');
      const env = { lineOffset, code: [], headings: [] };
      let out = md.render(body, env);
      if (frontMatter !== null) {
        out = `<details class="front-matter"><summary>Front matter</summary>` +
          `<pre>${escapeHtml(frontMatter)}</pre></details>\n` + out;
      }
      return { html: out, code: env.code, headings: env.headings };
    }

    return { render, md };
  }

  g.LegibleCore = { create, splitFrontMatter, slugify };
})();
