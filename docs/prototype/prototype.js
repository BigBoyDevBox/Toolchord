(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const commands = [
    { id: 'format', name: 'Format JSON', detail: 'Readable, without changing values', symbol: '{ }', aliases: 'pretty print beautify json' },
    { id: 'minify', name: 'Minify JSON', detail: 'Remove insignificant whitespace', symbol: '{ }', aliases: 'compact json' },
    { id: 'validate', name: 'Validate JSON', detail: 'Check syntax, preserve input', symbol: '✓', aliases: 'check json' },
    { id: 'uuid', name: 'Generate UUID', detail: 'A new version 4 identifier', symbol: '#', aliases: 'guid uuid random id' }
  ];
  const sample = '{"status":200,"requestId":9007199254740993,"cache":"HIT"}';
  const state = { payload: sample, query: '', selected: 'format', expanded: false, uuid: null, menu: false, closed: false, result: null };
  const announce = message => { $('announcement').textContent = message; };
  const command = () => commands.find(c => c.id === state.selected);
  function matches() {
    const query = state.query.toLowerCase().trim();
    if (!query) return commands;
    return commands.map((c, order) => {
      const name = c.name.toLowerCase();
      const aliases = c.aliases.split(' ');
      let rank = name === query || c.aliases === query || aliases.includes(query) ? 0 : name.startsWith(query) ? 1 : (name + ' ' + c.aliases).includes(query) ? 2 : 3;
      let position = 0;
      const haystack = name + ' ' + c.aliases;
      for (const letter of query) { position = haystack.indexOf(letter, position); if (position < 0) return null; position++; }
      return { c, rank, order };
    }).filter(Boolean).sort((a, b) => a.rank - b.rank || a.order - b.order).map(item => item.c);
  }
  // JSON.parse checks grammar only. Its parsed values never reach the output;
  // formatting operates on lexical tokens to retain precision and duplicates.
  function jsonText(input, mode) {
    JSON.parse(input);
    const tokens = input.match(/"(?:\\[\s\S]|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\]:,]/g);
    let nesting = 0;
    for (const token of tokens) {
      if (token === '{' || token === '[') nesting++;
      if (token === '}' || token === ']') nesting--;
      if (nesting > 128) throw new Error('JSON exceeds the 128-level nesting limit.');
    }
    if (mode === 'validate') return input;
    if (mode === 'minify') return tokens.join('');
    let depth = 0, result = '';
    const line = () => '\n' + '  '.repeat(depth);
    tokens.forEach((token, index) => {
      const previous = tokens[index - 1], next = tokens[index + 1];
      if (token === '{' || token === '[') {
        result += token; depth++;
        if (next !== '}' && next !== ']') result += line();
      } else if (token === '}' || token === ']') {
        depth--;
        if (previous !== '{' && previous !== '[') result += line();
        result += token;
      } else if (token === ',') result += ',' + line();
      else if (token === ':') result += ': ';
      else result += token;
      if (result.length > 4194304) throw new Error('Result exceeds the 4 MiB prototype limit.');
    });
    return result;
  }
  function evaluate() {
    if (!command()) return { ok: false, text: 'Choose a command to see its preview.', status: '' };
    if (state.selected === 'uuid') {
      if (!state.uuid) state.uuid = crypto.randomUUID();
      return { ok: true, text: state.uuid, status: 'UUID v4', label: 'Copy UUID & Close' };
    }
    if (state.payload === null) return { ok: false, text: 'Paste JSON to see a preview. Your clipboard is read only when you paste.', status: 'Needs input' };
    if (new TextEncoder().encode(state.payload).length > 1048576) return { ok: false, error: 'Input exceeds the 1 MiB prototype limit.', text: '', status: 'Too large' };
    try {
      const text = jsonText(state.payload, state.selected);
      if (new TextEncoder().encode(text).length > 4194304) throw new Error('Result exceeds the 4 MiB prototype limit.');
      return { ok: true, text, status: 'Valid JSON', label: state.selected === 'validate' ? 'Copy input & Close' : 'Copy JSON & Close' };
    } catch (error) {
      return { ok: false, error: String(error.message), text: '', status: 'Cannot copy' };
    }
  }
  function render() {
    const filtered = matches();
    if (!filtered.some(c => c.id === state.selected)) state.selected = filtered[0]?.id ?? null;
    state.result = evaluate();
    $('root-view').hidden = state.expanded;
    $('tool-view').hidden = !state.expanded;
    $('palette').hidden = state.closed;
    $('closed').hidden = !state.closed;
    $('search').value = state.query;
    $('attachment').hidden = state.payload === null;
    if (state.payload !== null) {
      const type = /^[\s]*[\[{]/.test(state.payload) ? 'JSON-like text' : 'Text';
      $('attachment-label').textContent = `Pasted input · ${type} · ${new TextEncoder().encode(state.payload).length} bytes`;
    }
    $('commands').replaceChildren(...filtered.map(c => {
      const button = document.createElement('button');
      button.type = 'button'; button.id = 'command-' + c.id; button.className = 'command';
      button.setAttribute('role', 'option'); button.setAttribute('aria-selected', String(c.id === state.selected));
      const symbol = document.createElement('span'); symbol.className = 'command-symbol'; symbol.textContent = c.symbol; symbol.setAttribute('aria-hidden', 'true');
      const label = document.createElement('span'); label.textContent = c.name;
      const detail = document.createElement('small'); detail.textContent = c.detail; label.append(detail); button.append(symbol, label);
      button.addEventListener('click', () => { state.selected = c.id; render(); $('search').focus(); });
      button.addEventListener('dblclick', openTool);
      button.addEventListener('keydown', event => { if (event.key === 'Enter' && !event.metaKey && !event.ctrlKey && !event.isComposing) { event.preventDefault(); state.selected = c.id; openTool(); } });
      return button;
    }));
    if (!filtered.length) { const empty = document.createElement('p'); empty.textContent = 'No tools found'; empty.className = 'no-results'; $('commands').append(empty); }
    $('clear-query').hidden = filtered.length > 0;
    if (state.selected) $('search').setAttribute('aria-activedescendant', 'command-' + state.selected);
    else $('search').removeAttribute('aria-activedescendant');
    $('preview-title').textContent = command()?.name ?? 'Preview';
    $('preview').textContent = state.result.text;
    $('status').textContent = state.result.status;
    $('preview-error').hidden = !state.result.error; $('preview-error').textContent = state.result.error ?? '';
    $('tool-title').textContent = command()?.name ?? '';
    if ($('editor').value !== (state.payload ?? '')) $('editor').value = state.payload ?? '';
    $('input-label').hidden = state.selected === 'uuid';
    $('editors').classList.toggle('generator', state.selected === 'uuid');
    $('tool-output').textContent = state.result.text;
    $('tool-status').textContent = state.result.status;
    $('tool-error').hidden = !state.result.error; $('tool-error').textContent = state.result.error ?? '';
    $('regenerate').hidden = state.selected !== 'uuid';
    $('copy').disabled = !state.result.ok;
    $('copy').replaceChildren(document.createTextNode(state.result.label ?? 'Copy & Close'), Object.assign(document.createElement('kbd'), { textContent: '⌘↵' }));
    $('key-hints').textContent = state.expanded ? 'Esc Back · Return inserts a newline' : '↑↓ Navigate · ↵ Open · Esc Dismiss';
    $('action-menu').hidden = !state.menu; $('actions').setAttribute('aria-expanded', String(state.menu));
    $('copy-stay').disabled = !state.result.ok; $('as-search').disabled = state.payload === null;
    $('menu-clear').disabled = state.payload === null; $('menu-regenerate').hidden = state.selected !== 'uuid';
  }
  function openTool() {
    if (!command()) return;
    state.expanded = true; state.menu = false; render();
    (state.selected === 'uuid' ? $('regenerate') : $('editor')).focus();
  }
  function back() { state.expanded = false; state.menu = false; render(); $('search').focus(); }
  function clearInput() { state.payload = null; state.menu = false; render(); (state.expanded && state.selected !== 'uuid' ? $('editor') : $('search')).focus(); }
  function reset(payload = null, selected = 'format') {
    Object.assign(state, { payload, query: '', selected, expanded: false, uuid: null, menu: false, closed: false, result: null });
    render(); $('search').focus(); announce('Design prototype · Copy and dismissal are simulated; the system clipboard is unchanged.');
  }
  function close(copied) {
    const label = state.result?.label ?? '';
    Object.assign(state, { payload: null, query: '', selected: 'format', expanded: false, uuid: null, menu: false, closed: true, result: null });
    render();
    $('closed-message').textContent = copied ? `${label.replace(' & Close', '')} — simulated. Your system clipboard is unchanged.` : 'Dismissed. The session draft was cleared.';
    announce(copied ? 'Copy and close simulated. Clipboard unchanged.' : 'Session dismissed and cleared.'); $('reopen').focus();
  }
  function copy(stay = false) {
    if (!state.result?.ok) return;
    if (!stay) close(true);
    else { state.menu = false; render(); $('actions').focus(); announce('Copy simulated. Clipboard unchanged; the panel stays open.'); }
  }
  $('search').addEventListener('input', event => { state.query = event.target.value; state.selected = null; render(); });
  $('search').addEventListener('paste', event => {
    if (!event.clipboardData?.types.includes('text/plain')) { event.preventDefault(); announce('Paste text to attach input. Existing input was preserved.'); return; }
    event.preventDefault(); state.payload = event.clipboardData.getData('text/plain'); render(); announce('Input attached. Preview updated.');
  });
  $('search').addEventListener('keydown', event => {
    if (event.isComposing) return;
    if (event.key === 'ArrowDown' || event.key === 'ArrowUp') {
      event.preventDefault(); const list = matches(), index = list.findIndex(c => c.id === state.selected);
      if (list.length) state.selected = list[(index + (event.key === 'ArrowDown' ? 1 : -1) + list.length) % list.length].id;
      render();
    } else if (event.key === 'Enter' && !event.metaKey && !event.ctrlKey) { event.preventDefault(); openTool(); }
  });
  $('editor').addEventListener('input', event => { state.payload = event.target.value; render(); });
  $('back').addEventListener('click', back);
  $('clear').addEventListener('click', clearInput); $('menu-clear').addEventListener('click', clearInput);
  $('clear-query').addEventListener('click', () => { state.query = ''; render(); $('search').focus(); });
  $('copy').addEventListener('click', () => copy()); $('copy-stay').addEventListener('click', () => copy(true));
  const regenerate = () => { state.uuid = crypto.randomUUID(); state.menu = false; render(); $('regenerate').hidden ? $('actions').focus() : $('regenerate').focus(); announce('New UUID generated.'); };
  $('regenerate').addEventListener('click', regenerate); $('menu-regenerate').addEventListener('click', regenerate);
  function toggleMenu() { state.menu = !state.menu; render(); if (state.menu) $('copy-stay').disabled ? $('menu-clear').disabled ? $('actions').focus() : $('menu-clear').focus() : $('copy-stay').focus(); else $('actions').focus(); }
  $('actions').addEventListener('click', toggleMenu);
  $('as-search').addEventListener('click', () => { state.query = state.payload ?? ''; state.payload = null; state.menu = false; state.expanded = false; render(); $('search').focus(); });
  $('sample').addEventListener('click', () => reset(sample)); $('invalid').addEventListener('click', () => reset('{"status":200,}'));
  $('uuid-scenario').addEventListener('click', () => reset(null, 'uuid')); $('reset').addEventListener('click', () => reset()); $('reopen').addEventListener('click', () => reset());
  $('palette').addEventListener('keydown', event => {
    if (event.isComposing) return;
    if (event.metaKey && event.key.toLowerCase() === 'k') { event.preventDefault(); toggleMenu(); }
    else if (event.metaKey && event.key === 'Enter') { event.preventDefault(); if (!state.menu) copy(); }
    else if (event.key === 'Escape') { event.preventDefault(); if (state.menu) { state.menu = false; render(); $('actions').focus(); } else if (state.expanded) back(); else close(false); }
  });
  render();
})();
