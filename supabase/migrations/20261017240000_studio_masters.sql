-- NOYA Studio master systems (17 Oct 2026): every stage of Reply / Meeting → Concept → Brief → Proposal → Project is now a
-- Studio document, so studio_documents records the internal ones too (opportunity notes, project books, operations
-- itineraries) and the NOYA Private services overview. Each record says which master (vertical), which stage and who it is
-- for (CLIENT or INTERNAL). Internal documents are never sent. Status is still set by Adam; nothing sends from here.

alter table public.studio_documents drop constraint if exists studio_documents_doc_type_check;
alter table public.studio_documents add constraint studio_documents_doc_type_check
  check (doc_type in ('OPPORTUNITY_NOTE', 'CONCEPT', 'BRIEF', 'PROPOSAL', 'PROJECT', 'ITINERARY', 'OPS_ITINERARY', 'DESK_BRIEF', 'PARTNER_DECK'));

alter table public.studio_documents add column if not exists vertical text
  check (vertical in ('brand', 'weddings', 'media', 'private', 'travel', 'corporate', 'retreat'));
alter table public.studio_documents add column if not exists stage text;
alter table public.studio_documents add column if not exists audience text not null default 'CLIENT'
  check (audience in ('CLIENT', 'INTERNAL'));

update public.studio_documents set vertical = 'brand', stage = lower(doc_type) where vertical is null;

create index if not exists studio_documents_company_idx on public.studio_documents (company_id, created_at desc);

comment on table public.studio_documents is 'NOYA Studio outputs: opportunity notes, concepts, briefs, proposals, project books, itineraries and NOYA Private overviews, per version, with sources and review notes. INTERNAL documents are never sent. No client access; nothing sends from here.';
