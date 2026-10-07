import './styles/base.css';
import './styles/site.css';
import './styles/studio.css';
import './styles/color.css';
import { h, mount } from './lib/dom';
import { route, setNotFound, startRouter, onNavigate } from './lib/router';
import { linkButton } from './lib/ui';
import { homePage } from './public/home';
import { artistPage } from './public/artist';
import { bookPage } from './public/book';
import { bridalPage, managePage, privacyPage } from './public/forms';
import { publicShell } from './public/layout';
import { signInPage, joinPage, forgotPage, resetPage } from './auth/pages';
import { studio } from './studio/shell';
import { overviewPage } from './studio/overview';
import { calendarPage } from './studio/calendar';
import { bookingsPage, clientsPage, enquiriesPage, messagesPage } from './studio/lists';
import { servicesPage, availabilityPage, galleryPage, reportsPage, teamPage, settingsPage, auditPage, accountPage } from './studio/manage';

const app = document.getElementById('app')!;

onNavigate(() => {
  document.querySelectorAll('.dialog-backdrop').forEach((d) => d.remove());
  document.body.classList.remove('no-scroll');
  window.scrollTo({ top: 0 });
});

route('/', () => homePage(app));
route('/artists/:slug', ({ params }) => artistPage(app, params.slug));
route('/book', ({ query }) => bookPage(app, query));
route('/bridal', ({ query }) => bridalPage(app, query));
route('/manage', () => managePage(app));
route('/privacy', () => privacyPage(app));
route('/signin', () => signInPage(app));
route('/join', ({ query }) => joinPage(app, query));
route('/forgot', () => forgotPage(app));
route('/reset', () => resetPage(app));

route('/studio', ({ path }) => studio(app, path, overviewPage, { title: 'Overview' }));
route('/studio/calendar', ({ path }) => studio(app, path, calendarPage, { title: 'Calendar' }));
route('/studio/bookings', ({ path }) => studio(app, path, bookingsPage, { title: 'Bookings' }));
route('/studio/clients', ({ path }) => studio(app, path, clientsPage, { title: 'Clients' }));
route('/studio/enquiries', ({ path }) => studio(app, path, enquiriesPage, { title: 'Enquiries' }));
route('/studio/services', ({ path }) => studio(app, path, servicesPage, { title: 'Services' }));
route('/studio/availability', ({ path }) => studio(app, path, availabilityPage, { title: 'Availability' }));
route('/studio/gallery', ({ path }) => studio(app, path, galleryPage, { title: 'Gallery' }));
route('/studio/messages', ({ path }) => studio(app, path, messagesPage, { title: 'Calls & messages' }));
route('/studio/reports', ({ path }) => studio(app, path, reportsPage, { title: 'Reports' }));
route('/studio/team', ({ path }) => studio(app, path, teamPage, { title: 'Professionals', ownerOnly: true, scoped: false }));
route('/studio/settings', ({ path }) => studio(app, path, settingsPage, { title: 'Settings', ownerOnly: true, scoped: false }));
route('/studio/audit', ({ path }) => studio(app, path, auditPage, { title: 'Activity log', ownerOnly: true }));
route('/studio/account', ({ path }) => studio(app, path, accountPage, { title: 'Account', scoped: false }));

setNotFound(() => {
  document.title = 'Page not found · Shahina Ahmed';
  publicShell(app, null, [h('section', { class: 'container pad-y narrow' },
    h('h1', { class: 'page-title', text: 'We could not find that page' }),
    h('p', { class: 'muted', text: 'The link may be out of date.' }),
    h('p', { class: 'mt' }, linkButton('Go to the home page', '/')))]);
});

mount(app);
startRouter();
