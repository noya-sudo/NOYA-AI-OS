-- Hardening: pin search_path on the three pure helper functions flagged by the Supabase security advisor.
alter function public.hq_trim(text) set search_path = public;
alter function public.hq_parse_draft(text) set search_path = public;
alter function public.gmail_prelabel(text, text, text, text) set search_path = public;
