import { rpc } from '../lib/supabase';
import { SALON_SLUG } from '../config';

export interface PublicService {
  id: string; name: string; description: string | null; category: string; duration_min: number;
  price_pence: number | null; price_kind: 'fixed' | 'from' | 'enquire'; price_label: string; bookable_online: boolean;
}
export interface PublicPro {
  id: string; slug: string; display_name: string; short_name: string; specialty: string | null; bio: string | null;
  instagram_url: string | null; logo_path: string | null; color: string; online_booking: boolean; services: PublicService[];
}
export interface PublicSalon {
  id: string; slug: string; name: string; tagline: string | null; city: string | null; address: string | null;
  phone: string | null; whatsapp: string | null; email: string | null; instagram_url: string | null;
  booking_mode: 'closed' | 'preview' | 'live'; booking_policy: string | null; timezone: string;
  hours_confirmed: boolean; hours: { weekday: number; opens: string; closes: string }[] | null;
  min_notice_min: number; max_days_ahead: number; today: string;
}
export interface PublicProfile { salon: PublicSalon; professionals: PublicPro[] }

let cache: Promise<PublicProfile> | null = null;

export function loadProfile(force = false): Promise<PublicProfile> {
  if (!cache || force) {
    cache = rpc<any>('salon_public_profile', { p_salon: SALON_SLUG }, { anon: true }).then((r) => {
      if (!r?.ok) throw new Error(r?.message || 'This salon is not available right now.');
      return r as PublicProfile;
    });
    cache.catch(() => { cache = null; });
  }
  return cache;
}

export interface GalleryItem { id: string; professional_slug: string; professional: string; storage_path: string; media_type: 'image' | 'video'; alt_text: string; caption: string | null }

export async function loadGallery(pro?: string): Promise<GalleryItem[]> {
  const r = await rpc<any>('salon_public_gallery', { p_salon: SALON_SLUG, p_professional: pro ?? null }, { anon: true });
  return r?.ok ? r.items : [];
}

export function fromPrice(p: PublicPro): string | null {
  const priced = p.services.filter((s) => s.price_kind !== 'enquire' && s.price_pence !== null);
  if (!priced.length) return null;
  const min = Math.min(...priced.map((s) => s.price_pence as number));
  return `from £${min % 100 ? (min / 100).toFixed(2) : min / 100}`;
}
