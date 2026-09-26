// Public configuration only. The publishable key is designed to be shipped to
// browsers; every table is RLS deny-all and the only callable functions are the
// hq_* RPCs, which check the signed-in user against hq_admins.
// Never put a service-role / secret key in this file.
export const SUPABASE_URL = 'https://gagbhykzmtstekpqujyl.supabase.co';
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_iIMuUDfvhvTffeOz9XMNNw_fBD11gxV';
export const GMAIL_DRAFTS_URL = 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#drafts';
export const GMAIL_THREAD_URL = 'https://mail.google.com/mail/?authuser=noya@noyaconcierge.com#all/';
