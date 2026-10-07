import { h, icon, uid, append } from './dom';
import { STATUS_LABEL } from './format';

type BtnVariant = 'primary' | 'secondary' | 'ghost' | 'danger' | 'link';

export function button(label: string | Node, opts: {
  variant?: BtnVariant; size?: 'sm' | 'md' | 'lg'; icon?: string; iconRight?: string; type?: 'button' | 'submit';
  onClick?: (e: MouseEvent) => void; disabled?: boolean; full?: boolean; ariaLabel?: string; class?: string;
} = {}): HTMLButtonElement {
  return h('button', {
    class: ['btn', `btn-${opts.variant ?? 'primary'}`, `btn-${opts.size ?? 'md'}`, opts.full && 'btn-full', opts.class],
    attrs: { type: opts.type ?? 'button', 'aria-label': opts.ariaLabel, disabled: opts.disabled },
    on: opts.onClick ? { click: opts.onClick } : undefined,
  }, opts.icon ? icon(opts.icon, 17) : null, typeof label === 'string' ? h('span', { text: label }) : label, opts.iconRight ? icon(opts.iconRight, 17) : null);
}

export function linkButton(label: string, href: string, opts: { variant?: BtnVariant; size?: 'sm' | 'md' | 'lg'; icon?: string; iconRight?: string; external?: boolean; class?: string } = {}) {
  return h('a', {
    class: ['btn', `btn-${opts.variant ?? 'primary'}`, `btn-${opts.size ?? 'md'}`, opts.class],
    attrs: { href, target: opts.external ? '_blank' : undefined, rel: opts.external ? 'noopener noreferrer' : undefined },
  }, opts.icon ? icon(opts.icon, 17) : null, h('span', { text: label }), opts.iconRight ? icon(opts.iconRight, 17) : null);
}

export function setBusy(btn: HTMLButtonElement, busy: boolean, busyLabel = 'Please wait…') {
  if (busy) {
    btn.dataset.label = btn.querySelector('span')?.textContent ?? '';
    btn.disabled = true;
    btn.setAttribute('aria-busy', 'true');
    const s = btn.querySelector('span');
    if (s) s.textContent = busyLabel;
  } else {
    btn.disabled = false;
    btn.removeAttribute('aria-busy');
    const s = btn.querySelector('span');
    if (s && btn.dataset.label !== undefined) s.textContent = btn.dataset.label;
  }
}

export interface FieldOpts {
  label: string; name: string; type?: string; value?: string; required?: boolean; hint?: string; placeholder?: string;
  autocomplete?: string; inputmode?: string; maxlength?: number; min?: string; max?: string; step?: string; pattern?: string;
}

export function field(o: FieldOpts) {
  const id = uid(o.name);
  const hintId = `${id}-hint`;
  const errId = `${id}-err`;
  const input = h('input', {
    class: 'input',
    attrs: {
      id, name: o.name, type: o.type ?? 'text', required: o.required, placeholder: o.placeholder, autocomplete: o.autocomplete,
      inputmode: o.inputmode, maxlength: o.maxlength, min: o.min, max: o.max, step: o.step, pattern: o.pattern,
      'aria-describedby': [o.hint ? hintId : '', errId].filter(Boolean).join(' '),
    },
  });
  if (o.value !== undefined) input.value = o.value;
  const err = h('p', { class: 'field-error', attrs: { id: errId, role: 'alert' } });
  const wrap = h('div', { class: 'field' },
    h('label', { class: 'field-label', attrs: { for: id } }, o.label, o.required ? null : h('span', { class: 'field-optional', text: ' (optional)' })),
    input,
    o.hint ? h('p', { class: 'field-hint', attrs: { id: hintId }, text: o.hint }) : null,
    err);
  return { wrap, input, setError: (msg: string | null) => { err.textContent = msg ?? ''; input.setAttribute('aria-invalid', msg ? 'true' : 'false'); wrap.classList.toggle('has-error', !!msg); } };
}

export function textarea(o: { label: string; name: string; value?: string; hint?: string; rows?: number; maxlength?: number; required?: boolean; placeholder?: string }) {
  const id = uid(o.name);
  const ta = h('textarea', { class: 'input textarea', attrs: { id, name: o.name, rows: o.rows ?? 3, maxlength: o.maxlength, required: o.required, placeholder: o.placeholder } });
  if (o.value) ta.value = o.value;
  const err = h('p', { class: 'field-error', attrs: { role: 'alert' } });
  const wrap = h('div', { class: 'field' },
    h('label', { class: 'field-label', attrs: { for: id } }, o.label, o.required ? null : h('span', { class: 'field-optional', text: ' (optional)' })),
    ta, o.hint ? h('p', { class: 'field-hint', text: o.hint }) : null, err);
  return { wrap, input: ta, setError: (m: string | null) => { err.textContent = m ?? ''; wrap.classList.toggle('has-error', !!m); } };
}

export function select(o: { label: string; name: string; options: { value: string; label: string }[]; value?: string; hint?: string; hideLabel?: boolean }) {
  const id = uid(o.name);
  const sel = h('select', { class: 'input select', attrs: { id, name: o.name } },
    o.options.map((op) => h('option', { attrs: { value: op.value }, text: op.label })));
  if (o.value !== undefined) sel.value = o.value;
  const wrap = h('div', { class: 'field' },
    h('label', { class: ['field-label', o.hideLabel && 'sr-only'], attrs: { for: id }, text: o.label }),
    sel, o.hint ? h('p', { class: 'field-hint', text: o.hint }) : null);
  return { wrap, input: sel };
}

export function checkbox(o: { label: string | Node; name: string; checked?: boolean; hint?: string }) {
  const id = uid(o.name);
  const input = h('input', { attrs: { type: 'checkbox', id, name: o.name } });
  input.checked = !!o.checked;
  const wrap = h('div', { class: 'check' }, input,
    h('label', { attrs: { for: id } }, typeof o.label === 'string' ? o.label : o.label, o.hint ? h('span', { class: 'check-hint', text: o.hint }) : null));
  return { wrap, input };
}

export function spinner(label = 'Loading') {
  return h('div', { class: 'spinner-wrap', attrs: { role: 'status' } }, h('span', { class: 'spinner', attrs: { 'aria-hidden': 'true' } }), h('span', { class: 'sr-only', text: label }));
}

export function emptyState(title: string, body?: string, action?: Node) {
  return h('div', { class: 'empty' }, h('div', { class: 'empty-mark', attrs: { 'aria-hidden': 'true' } }, icon('sparkle', 20)),
    h('p', { class: 'empty-title', text: title }), body ? h('p', { class: 'empty-body', text: body }) : null, action ?? null);
}

export function errorBox(message: string, retry?: () => void) {
  return h('div', { class: 'notice notice-error', attrs: { role: 'alert' } }, icon('alert', 18),
    h('div', null, h('p', { text: message }), retry ? button('Try again', { variant: 'link', onClick: retry }) : null));
}

export function notice(kind: 'info' | 'warn' | 'success' | 'error', content: string | Node, iconName?: string) {
  return h('div', { class: ['notice', `notice-${kind}`], attrs: { role: kind === 'error' ? 'alert' : 'note' } },
    icon(iconName ?? (kind === 'success' ? 'check' : kind === 'info' ? 'info' : 'alert'), 18),
    typeof content === 'string' ? h('p', { text: content }) : content);
}

export function statusBadge(status: string) {
  return h('span', { class: ['badge', `badge-${status}`], text: STATUS_LABEL[status] ?? status });
}

export function proDot(color: string) {
  return h('span', { class: ['pro-dot', `pro-${color}`], attrs: { 'aria-hidden': 'true' } });
}

// ---------------------------------------------------------------- toast
let toastRoot: HTMLElement | null = null;
export function toast(message: string, kind: 'success' | 'error' | 'info' = 'success') {
  if (!toastRoot) {
    toastRoot = h('div', { class: 'toasts', attrs: { 'aria-live': 'polite', 'aria-atomic': 'false' } });
    document.body.appendChild(toastRoot);
  }
  const t = h('div', { class: ['toast', `toast-${kind}`], attrs: { role: kind === 'error' ? 'alert' : 'status' } },
    icon(kind === 'success' ? 'check' : kind === 'error' ? 'alert' : 'info', 17), h('span', { text: message }));
  toastRoot.appendChild(t);
  setTimeout(() => { t.classList.add('toast-out'); setTimeout(() => t.remove(), 300); }, kind === 'error' ? 6000 : 3500);
}

// ---------------------------------------------------------------- modal / drawer
export interface Dialog { close: () => void; body: HTMLElement; footer: HTMLElement; panel: HTMLElement; setTitle: (t: string) => void }

export function openDialog(o: { title: string; kind?: 'modal' | 'drawer'; size?: 'sm' | 'md' | 'lg'; onClose?: () => void; subtitle?: string }): Dialog {
  const prevFocus = document.activeElement as HTMLElement | null;
  const titleId = uid('dlg');
  const titleEl = h('h2', { class: 'dialog-title', attrs: { id: titleId }, text: o.title });
  const body = h('div', { class: 'dialog-body' });
  const footer = h('div', { class: 'dialog-footer' });
  const closeBtn = button('', { variant: 'ghost', size: 'sm', icon: 'x', ariaLabel: 'Close', class: 'dialog-close' });
  const panel = h('div', { class: ['dialog-panel', `dialog-${o.kind ?? 'modal'}`, `dialog-${o.size ?? 'md'}`], attrs: { role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': titleId, tabindex: '-1' } },
    h('div', { class: 'dialog-head' }, h('div', null, titleEl, o.subtitle ? h('p', { class: 'dialog-sub', text: o.subtitle }) : null), closeBtn),
    body, footer);
  const backdrop = h('div', { class: ['dialog-backdrop', `backdrop-${o.kind ?? 'modal'}`] }, panel);
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    document.removeEventListener('keydown', onKey, true);
    backdrop.classList.add('closing');
    document.body.classList.remove('no-scroll');
    setTimeout(() => backdrop.remove(), 180);
    prevFocus?.focus?.();
    o.onClose?.();
  };
  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'Escape') { e.preventDefault(); close(); }
    if (e.key === 'Tab') {
      const f = Array.from(panel.querySelectorAll<HTMLElement>('a[href],button:not([disabled]),input:not([disabled]),select:not([disabled]),textarea:not([disabled]),[tabindex]:not([tabindex="-1"])')).filter((x) => x.offsetParent !== null);
      if (!f.length) return;
      const first = f[0]; const last = f[f.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  };
  closeBtn.addEventListener('click', close);
  backdrop.addEventListener('mousedown', (e) => { if (e.target === backdrop) close(); });
  document.addEventListener('keydown', onKey, true);
  document.body.appendChild(backdrop);
  document.body.classList.add('no-scroll');
  requestAnimationFrame(() => panel.focus());
  return { close, body, footer, panel, setTitle: (t) => { titleEl.textContent = t; } };
}

export function confirmDialog(o: { title: string; message: string; confirmLabel: string; danger?: boolean; reasonLabel?: string }): Promise<{ ok: boolean; reason: string }> {
  return new Promise((resolve) => {
    let done = false;
    const d = openDialog({ title: o.title, size: 'sm', onClose: () => { if (!done) resolve({ ok: false, reason: '' }); } });
    append(d.body, h('p', { class: 'muted', text: o.message }));
    let reasonInput: HTMLTextAreaElement | null = null;
    if (o.reasonLabel) {
      const t = textarea({ label: o.reasonLabel, name: 'reason', rows: 2, maxlength: 300 });
      reasonInput = t.input;
      append(d.body, t.wrap);
    }
    append(d.footer,
      button('Keep it', { variant: 'secondary', onClick: () => d.close() }),
      button(o.confirmLabel, { variant: o.danger ? 'danger' : 'primary', onClick: () => { done = true; resolve({ ok: true, reason: reasonInput?.value.trim() ?? '' }); d.close(); } }));
  });
}

export function sectionHead(title: string, sub?: string, actions?: Node[]) {
  return h('div', { class: 'section-head' },
    h('div', null, h('h2', { class: 'section-title', text: title }), sub ? h('p', { class: 'section-sub', text: sub }) : null),
    actions?.length ? h('div', { class: 'section-actions' }, actions) : null);
}
