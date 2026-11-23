-- ============================================================
-- Under Wraps — update 2: wish lists
-- Run once in Supabase → SQL Editor → New query, AFTER schema.sql.
--
-- How the secret is kept: a wish is just a wish (everyone in the family
-- can see it, including you). When someone taps "I'll get it", the app
-- logs a normal gift linked to that wish. Gifts for you are already
-- hidden from you by the database, so you can never tell which of your
-- wishes have been bought.
-- ============================================================

create table public.wishes (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  person      uuid not null,
  title       text not null check (char_length(title) between 1 and 80),
  link        text not null default '' check (char_length(link) <= 500),
  price       numeric(10,2) not null default 0 check (price >= 0),
  notes       text not null default '' check (char_length(notes) <= 300),
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  foreign key (person, family_id) references public.people (id, family_id) on delete cascade
);
create index wishes_family_idx on public.wishes (family_id);

-- You manage your own wish list. Anyone in the family can manage the
-- list of someone without an account (like the kids).
create or replace function public.can_manage_wish(pid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from people
    where id = pid and (claimed_by = auth.uid() or claimed_by is null) and is_member(family_id)
  );
$$;

alter table public.wishes enable row level security;

create policy "wishes: read"   on public.wishes for select to authenticated using (public.is_member(family_id));
create policy "wishes: add"    on public.wishes for insert to authenticated
  with check (public.is_member(family_id) and public.can_manage_wish(person));
create policy "wishes: edit"   on public.wishes for update to authenticated
  using (public.can_manage_wish(person)) with check (public.can_manage_wish(person));
create policy "wishes: remove" on public.wishes for delete to authenticated using (public.can_manage_wish(person));

revoke all on public.wishes from anon, authenticated;
grant select, insert, delete on public.wishes to authenticated;
grant update (title, link, price, notes) on public.wishes to authenticated;
revoke execute on function public.can_manage_wish(uuid) from public, anon;
grant  execute on function public.can_manage_wish(uuid) to authenticated;

-- Link a gift to the wish it fulfils
alter table public.gifts add column wish_id uuid references public.wishes(id) on delete set null;
grant update (wish_id) on public.gifts to authenticated;

alter publication supabase_realtime add table public.wishes;
