// Public, non-secret configuration. The publishable key only allows what the
// database grants to the `anon` role (the salon_public_* functions).
// Never put a service-role / secret key in this file or anywhere in the browser.
declare const __SUPABASE_URL__: string;
declare const __SUPABASE_PUBLISHABLE_KEY__: string;
declare const __SALON_SLUG__: string;
declare const __BUILD_ID__: string;

export const SUPABASE_URL = __SUPABASE_URL__;
export const SUPABASE_KEY = __SUPABASE_PUBLISHABLE_KEY__;
export const SALON_SLUG = __SALON_SLUG__;
export const BUILD_ID = __BUILD_ID__;
export const PORTFOLIO_BUCKET = 'portfolio';
export const TIMEZONE = 'Europe/London';
