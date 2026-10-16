-- NOYA Studio (17 Oct 2026): one record per document Studio produces (Brief, Concept, Proposal). The content file
-- (studio/documents/<slug>.json) is the source; the PDF is rendered from it. Sources and review notes travel with the record
-- so every claim in a client document can be traced. Status is set by Adam: nothing is sent from here.

create table if not exists public.studio_documents (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  version int not null default 1,
  doc_type text not null check (doc_type in ('BRIEF', 'CONCEPT', 'PROPOSAL', 'ITINERARY', 'PARTNER_DECK', 'OPS_ITINERARY')),
  title text not null,
  company_id uuid references public.companies(id),
  opportunity_id uuid references public.opportunities(id),
  prepared_for text,
  status text not null default 'FOR_REVIEW' check (status in ('DRAFT', 'FOR_REVIEW', 'APPROVED', 'SENT', 'SUPERSEDED')),
  content jsonb not null,
  sources jsonb not null default '[]'::jsonb,
  review_notes jsonb not null default '[]'::jsonb,
  source_path text,
  file_name text,
  file_location text,
  logo text,
  qa jsonb,
  created_at timestamptz not null default now(),
  created_by text not null default 'Studio',
  approved_at timestamptz,
  sent_at timestamptz,
  unique (slug, version)
);
alter table public.studio_documents enable row level security;
revoke all on table public.studio_documents from public, anon, authenticated;
comment on table public.studio_documents is 'NOYA Studio outputs (Brief, Concept, Proposal). Content, sources and review notes per version. No client access; nothing sends from here.';
