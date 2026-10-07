import { h, icon, mount } from '../lib/dom';
import { button, field, notice, setBusy, linkButton } from '../lib/ui';
import { signIn, signOut, requestPasswordReset, updatePassword, adoptSessionFromHash, callFunction, rpc, currentSession, ApiError } from '../lib/supabase';
import { navigate } from '../lib/router';
import { loadMe, primaryMembership } from './session';

function authShell(app: HTMLElement, title: string, lede: string, body: Node[]) {
  document.body.className = 'auth';
  document.title = `${title} · Shahina Ahmed Luxury Salon`;
  mount(app, h('main', { class: 'auth-page', attrs: { id: 'main' } },
    h('div', { class: 'auth-art', attrs: { 'aria-hidden': 'true' } },
      h('div', { class: 'auth-arch' }, h('img', { attrs: { src: '/brand/sa-monogram-light.svg', alt: '', width: 160, height: 160 } })),
      h('img', { class: 'auth-lockup', attrs: { src: '/brand/shahina-ahmed-lockup-light.svg', alt: '', width: 300, height: 80 } })),
    h('div', { class: 'auth-panel' },
      h('a', { class: 'auth-back', attrs: { href: '/' } }, icon('chevronLeft', 16), h('span', { text: 'Back to the website' })),
      h('div', { class: 'auth-card' },
        h('img', { class: 'auth-mark', attrs: { src: '/brand/sa-monogram.svg', alt: 'Shahina Ahmed', width: 56, height: 56 } }),
        h('h1', { class: 'auth-title', text: title }),
        h('p', { class: 'auth-lede', text: lede }),
        body))));
}

// --------------------------------------------------------------------- sign in
export async function signInPage(app: HTMLElement) {
  if (currentSession()) {
    const m = await loadMe().catch(() => null);
    if (primaryMembership(m)) { navigate('/studio', { replace: true }); return; }
  }
  const fEmail = field({ label: 'Email', name: 'email', type: 'email', required: true, autocomplete: 'username' });
  const fPass = field({ label: 'Password', name: 'password', type: 'password', required: true, autocomplete: 'current-password' });
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  const submit = button('Sign in', { type: 'submit', full: true, size: 'lg' });
  const form = h('form', { attrs: { novalidate: true } }, fEmail.wrap, fPass.wrap, err, submit,
    h('div', { class: 'auth-links' },
      h('a', { attrs: { href: '/forgot' }, text: 'Forgot your password?' }),
      h('a', { attrs: { href: '/join' }, text: 'I have an invitation code' })));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    mount(err);
    const email = fEmail.input.value.trim(); const password = fPass.input.value;
    if (!email || !password) { mount(err, notice('error', 'Enter your email and password.')); return; }
    setBusy(submit, true, 'Signing in…');
    try {
      await signIn(email, password);
      const m = await loadMe(true);
      if (!primaryMembership(m)) {
        await signOut();
        setBusy(submit, false);
        mount(err, notice('error', 'This account does not have access to the salon studio. If you were invited, use your invitation code.'));
        return;
      }
      navigate('/studio', { replace: true });
    } catch (ex) {
      setBusy(submit, false);
      mount(err, notice('error', (ex as Error).message));
    }
  });
  authShell(app, 'Staff sign in', 'For Shahina and the salon’s artists. Each person signs in with their own account.', [form]);
}

// --------------------------------------------------------------------- accept invitation
export async function joinPage(app: HTMLElement, query: URLSearchParams) {
  const signedIn = currentSession();
  const fCode = field({ label: 'Invitation code', name: 'code', required: true, autocomplete: 'one-time-code', placeholder: 'XXXX-XXXX-XXXX-XXXX', value: query.get('code') ?? '' });
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });

  if (signedIn) {
    const submit = button('Add access to my account', { type: 'submit', full: true, size: 'lg' });
    const form = h('form', { attrs: { novalidate: true } }, fCode.wrap, err, submit);
    form.addEventListener('submit', async (e) => {
      e.preventDefault(); mount(err); setBusy(submit, true, 'Checking…');
      try {
        await rpc('salon_claim_invite', { p_code: fCode.input.value });
        await loadMe(true);
        navigate('/studio', { replace: true });
      } catch (ex) { setBusy(submit, false); mount(err, notice('error', (ex as Error).message)); }
    });
    authShell(app, 'Use an invitation', `You are signed in as ${signedIn.user.email}. Enter the code the salon owner gave you.`, [form]);
    return;
  }

  const fName = field({ label: 'Your name', name: 'name', required: true, autocomplete: 'name', maxlength: 80 });
  const fEmail = field({ label: 'Email', name: 'email', type: 'email', required: true, autocomplete: 'username', hint: 'Use the email address the owner invited.' });
  const fPass = field({ label: 'Create a password', name: 'password', type: 'password', required: true, autocomplete: 'new-password', hint: 'At least 10 characters.' });
  const submit = button('Create my account', { type: 'submit', full: true, size: 'lg' });
  const form = h('form', { attrs: { novalidate: true } }, fCode.wrap, fName.wrap, fEmail.wrap, fPass.wrap, err, submit,
    h('div', { class: 'auth-links' }, h('a', { attrs: { href: '/signin' }, text: 'I already have an account' })));
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    mount(err); [fCode, fName, fEmail, fPass].forEach((f) => f.setError(null));
    let ok = true;
    if (fCode.input.value.replace(/[^A-Za-z0-9]/g, '').length !== 16) { fCode.setError('The code has 16 letters and numbers.'); ok = false; }
    if (fName.input.value.trim().length < 2) { fName.setError('Enter your name.'); ok = false; }
    if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(fEmail.input.value.trim())) { fEmail.setError('Enter a valid email address.'); ok = false; }
    if (fPass.input.value.length < 10) { fPass.setError('Use at least 10 characters.'); ok = false; }
    if (!ok) return;
    setBusy(submit, true, 'Creating your account…');
    try {
      const r = await callFunction<any>('accept-invite', { code: fCode.input.value, name: fName.input.value.trim(), email: fEmail.input.value.trim(), password: fPass.input.value });
      if (!r.data?.ok) {
        setBusy(submit, false);
        const code = r.data?.error;
        if (code === 'account_exists') {
          mount(err, notice('info', h('div', null, h('p', { text: r.data.message }), h('p', null, h('a', { attrs: { href: `/signin` }, text: 'Go to sign in' })))));
        } else if (code === 'weak_password') fPass.setError(r.data.message);
        else if (code === 'invite_email_mismatch' || code === 'email_invalid') fEmail.setError(r.data.message);
        else if (code?.startsWith('invite_')) fCode.setError(r.data.message);
        else mount(err, notice('error', r.data?.message || 'Something went wrong. Please try again.'));
        return;
      }
      await signIn(fEmail.input.value.trim(), fPass.input.value);
      await loadMe(true);
      navigate('/studio', { replace: true });
    } catch (ex) {
      setBusy(submit, false);
      mount(err, notice('error', (ex as Error).message));
    }
  });
  authShell(app, 'Create your studio account', 'The salon owner gives each artist a one-time invitation code. It works once, for the invited email address.', [form]);
}

// --------------------------------------------------------------------- forgot / reset
export function forgotPage(app: HTMLElement) {
  const fEmail = field({ label: 'Email', name: 'email', type: 'email', required: true, autocomplete: 'username' });
  const err = h('div', { attrs: { 'aria-live': 'polite' } });
  const submit = button('Send reset link', { type: 'submit', full: true, size: 'lg' });
  const form = h('form', { attrs: { novalidate: true } }, fEmail.wrap, err, submit,
    h('div', { class: 'auth-links' }, h('a', { attrs: { href: '/signin' }, text: 'Back to sign in' })));
  form.addEventListener('submit', async (e) => {
    e.preventDefault(); mount(err);
    const email = fEmail.input.value.trim();
    if (!/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(email)) { fEmail.setError('Enter a valid email address.'); return; }
    fEmail.setError(null);
    setBusy(submit, true, 'Sending…');
    try {
      await requestPasswordReset(email, `${location.origin}/reset`);
      mount(form, notice('success', 'If an account exists for that email, a reset link is on its way. It expires after a short time.'),
        h('p', { class: 'mt' }, linkButton('Back to sign in', '/signin', { variant: 'ghost' })));
    } catch (ex) {
      setBusy(submit, false);
      mount(err, notice('error', (ex as Error).message));
    }
  });
  authShell(app, 'Reset your password', 'We will email you a link to choose a new password.', [form]);
}

export function resetPage(app: HTMLElement) {
  const handed = location.hash ? adoptSessionFromHash(location.hash) : { session: null, type: null, error: null };
  if (location.hash) history.replaceState(null, '', '/reset'); // remove tokens from the address bar
  if (handed.error || !currentSession()) {
    authShell(app, 'Link expired', 'This password reset link is no longer valid.', [
      notice('error', handed.error || 'Request a new link and use it straight away.'),
      h('p', { class: 'mt' }, linkButton('Request a new link', '/forgot'))]);
    return;
  }
  const fPass = field({ label: 'New password', name: 'password', type: 'password', required: true, autocomplete: 'new-password', hint: 'At least 10 characters.' });
  const fPass2 = field({ label: 'Repeat new password', name: 'password2', type: 'password', required: true, autocomplete: 'new-password' });
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  const submit = button('Save new password', { type: 'submit', full: true, size: 'lg' });
  const form = h('form', { attrs: { novalidate: true } }, fPass.wrap, fPass2.wrap, err, submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault(); mount(err); fPass.setError(null); fPass2.setError(null);
    if (fPass.input.value.length < 10) { fPass.setError('Use at least 10 characters.'); return; }
    if (fPass.input.value !== fPass2.input.value) { fPass2.setError('The passwords do not match.'); return; }
    setBusy(submit, true, 'Saving…');
    try {
      await updatePassword(fPass.input.value);
      navigate('/studio', { replace: true });
    } catch (ex) {
      setBusy(submit, false);
      mount(err, notice('error', ex instanceof ApiError ? ex.message : 'Could not save the password.'));
    }
  });
  authShell(app, 'Choose a new password', `For ${currentSession()?.user.email ?? 'your account'}.`, [form]);
}
