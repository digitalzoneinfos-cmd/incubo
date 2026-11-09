-- =====================================================================
--  Incubo : installation de la base Supabase
--  À coller en entier dans Supabase > SQL Editor > New query, puis « Run ».
--  On peut le relancer sans risque : il ne supprime aucune donnée.
-- =====================================================================

-- 1. Une seule table qui contient tous les contenus de l'app et de l'admin
create table if not exists public.cms (
  collection text not null,              -- pubs, events, gallery, faq, stats, notifs, forms, startups, subs, questions, emails, settings
  id         text not null,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (collection, id)
);

alter table public.cms enable row level security;

-- 2. Règles d'accès
-- Tout le monde (les étudiants) peut lire les contenus publics de l'app
drop policy if exists "lecture publique des contenus" on public.cms;
create policy "lecture publique des contenus" on public.cms
  for select to anon, authenticated
  using (collection in ('pubs','events','gallery','faq','stats','notifs','forms')
         or (collection = 'settings' and id = 'contact'));

-- L'administration connectée peut tout lire et tout modifier
drop policy if exists "administration : lecture" on public.cms;
create policy "administration : lecture" on public.cms
  for select to authenticated using (true);

drop policy if exists "administration : écriture" on public.cms;
create policy "administration : écriture" on public.cms
  for all to authenticated using (true) with check (true);

-- Les étudiants peuvent seulement ENVOYER une inscription ou une question (jamais lire celles des autres)
drop policy if exists "étudiants : envoi" on public.cms;
create policy "étudiants : envoi" on public.cms
  for insert to anon
  with check (
    (collection = 'subs' and data->>'status' = 'Nouveau')
    or (collection = 'questions' and data->>'status' = 'wait')
  );

-- 3. Fonctions sûres pour l'app
-- Nombre d'inscrits par formulaire (pour afficher les places restantes), sans exposer les inscrits
create or replace function public.form_counts()
returns table(form_id text, n bigint)
language sql security definer set search_path = public as $$
  select data->>'formId', count(*) from public.cms where collection = 'subs' group by 1;
$$;

-- Réponse à une question, uniquement pour celui qui connaît l'identifiant de sa question
create or replace function public.question_replies(ids text[])
returns table(id text, status text, reply text)
language sql security definer set search_path = public as $$
  select c.id, c.data->>'status', c.data->>'reply'
  from public.cms c where c.collection = 'questions' and c.id = any(ids);
$$;

grant execute on function public.form_counts() to anon, authenticated;
grant execute on function public.question_replies(text[]) to anon, authenticated;

-- 4. Mises à jour en direct dans le tableau de bord
do $$ begin
  alter publication supabase_realtime add table public.cms;
exception when duplicate_object then null; end $$;

-- 5. Stockage des fichiers
--   media : images publiques (couvertures, galerie, logos)
--   docs  : documents privés des startups (labels, registres…), visibles seulement par l'administration
insert into storage.buckets (id, name, public) values ('media', 'media', true)
  on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('docs', 'docs', false)
  on conflict (id) do update set public = false;

drop policy if exists "admin : envoyer des fichiers" on storage.objects;
create policy "admin : envoyer des fichiers" on storage.objects
  for insert to authenticated with check (bucket_id in ('media','docs'));

drop policy if exists "admin : lire les documents" on storage.objects;
create policy "admin : lire les documents" on storage.objects
  for select to authenticated using (bucket_id in ('media','docs'));

drop policy if exists "admin : modifier les fichiers" on storage.objects;
create policy "admin : modifier les fichiers" on storage.objects
  for update to authenticated using (bucket_id in ('media','docs'));

drop policy if exists "admin : supprimer les fichiers" on storage.objects;
create policy "admin : supprimer les fichiers" on storage.objects
  for delete to authenticated using (bucket_id in ('media','docs'));

-- Terminé. Message attendu en bas : « Success. No rows returned ».
