-- ============================================================
-- Under Wraps — Supabase database setup
-- Paste this whole file into Supabase → SQL Editor → New query,
-- then press Run. Safe to run once on a fresh project.
-- ============================================================

-- ---------- Tables ----------

create table public.families (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(name) between 1 and 40),
  occasion    text not null default '' check (char_length(occasion) <= 40),
  code        text not null unique,
  created_by  uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now()
);

-- Which accounts belong to which family
create table public.members (
  family_id  uuid not null references public.families(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  joined_at  timestamptz not null default now(),
  primary key (family_id, user_id)
);

-- Everyone you buy for (kids without phones included).
-- claimed_by links a person to the account that "is" them.
create table public.people (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  name        text not null check (char_length(name) between 1 and 40),
  budget      numeric(10,2) not null default 0 check (budget >= 0),
  claimed_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (id, family_id)
);
-- One account can only be one person per family
create unique index people_one_claim_per_family
  on public.people (family_id, claimed_by) where claimed_by is not null;

create table public.gifts (
  id          uuid primary key default gen_random_uuid(),
  family_id   uuid not null references public.families(id) on delete cascade,
  title       text not null check (char_length(title) between 1 and 80),
  recipient   uuid not null,
  buyer       uuid,
  price       numeric(10,2) not null default 0 check (price >= 0),
  status      text not null default 'bought' check (status in ('idea','bought','wrapped','given')),
  store       text not null default '' check (char_length(store) <= 60),
  notes       text not null default '' check (char_length(notes) <= 300),
  logged_by   uuid references auth.users(id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- recipient and buyer must be people in the same family
  foreign key (recipient, family_id) references public.people (id, family_id),
  foreign key (buyer, family_id) references public.people (id, family_id) on delete set null (buyer)
);
create index gifts_family_idx on public.gifts (family_id);

-- Personal spending limits: only the owner can ever read these
create table public.limits (
  family_id  uuid not null references public.families(id) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade default auth.uid(),
  amount     numeric(10,2) not null default 0 check (amount >= 0),
  primary key (family_id, user_id)
);

-- ---------- Helper functions (used by the security rules) ----------

create or replace function public.is_member(fid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from members where family_id = fid and user_id = auth.uid());
$$;

-- The person in this family that the signed-in account has claimed (or null)
create or replace function public.my_person(fid uuid)
returns uuid language sql stable security definer set search_path = public as $$
  select id from people where family_id = fid and claimed_by = auth.uid() limit 1;
$$;

-- ---------- Row Level Security ----------

alter table public.families enable row level security;
alter table public.members  enable row level security;
alter table public.people   enable row level security;
alter table public.gifts    enable row level security;
alter table public.limits   enable row level security;

-- Families: members can see and rename. Creating happens through create_family().
create policy "families: members read"   on public.families for select to authenticated using (public.is_member(id));
create policy "families: members update" on public.families for update to authenticated using (public.is_member(id)) with check (public.is_member(id));

-- Members: see who else is in your family; leave whenever you like.
create policy "members: read own families" on public.members for select to authenticated using (public.is_member(family_id));
create policy "members: leave"             on public.members for delete to authenticated using (user_id = auth.uid());

-- People: members can read, add, edit. You can only add yourself as "claimed", never someone else.
create policy "people: read"   on public.people for select to authenticated using (public.is_member(family_id));
create policy "people: add"    on public.people for insert to authenticated
  with check (public.is_member(family_id) and (claimed_by is null or claimed_by = auth.uid()));
create policy "people: edit"   on public.people for update to authenticated using (public.is_member(family_id)) with check (public.is_member(family_id));
create policy "people: remove" on public.people for delete to authenticated using (public.is_member(family_id) and claimed_by is null);

-- Gifts: the important one. You only see gifts once you've picked your name,
-- and gifts FOR you never leave the server to your phone.
create policy "gifts: read" on public.gifts for select to authenticated
  using (public.is_member(family_id) and public.my_person(family_id) is not null and recipient <> public.my_person(family_id));
create policy "gifts: add" on public.gifts for insert to authenticated
  with check (public.is_member(family_id) and public.my_person(family_id) is not null and recipient <> public.my_person(family_id));
create policy "gifts: edit" on public.gifts for update to authenticated
  using (public.is_member(family_id) and recipient <> public.my_person(family_id))
  with check (public.is_member(family_id) and recipient <> public.my_person(family_id));
create policy "gifts: delete" on public.gifts for delete to authenticated
  using (public.is_member(family_id) and recipient <> public.my_person(family_id));

-- Limits: yours alone.
create policy "limits: own" on public.limits for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and public.is_member(family_id));

-- ---------- What the app may touch (explicit, so it works on new and old projects) ----------
-- Signed-out visitors get nothing. Signed-in users get only what the app needs,
-- and only certain columns can be edited after creation.
revoke all on public.families, public.members, public.people, public.gifts, public.limits from anon, authenticated;
grant select                          on public.families to authenticated;
grant update (name, occasion)         on public.families to authenticated;
grant select, delete                  on public.members  to authenticated;
grant select, insert, delete          on public.people   to authenticated;
grant update (name, budget)           on public.people   to authenticated;
grant select, insert, delete          on public.gifts    to authenticated;
grant update (title, recipient, buyer, price, status, store, notes, updated_at) on public.gifts to authenticated;
grant select, insert, update, delete  on public.limits   to authenticated;
revoke execute on function public.is_member(uuid), public.my_person(uuid) from public, anon;
grant  execute on function public.is_member(uuid), public.my_person(uuid) to authenticated;

-- ---------- Actions the app calls ----------

-- Start a family: makes the family, a join code, your membership and your person
create or replace function public.create_family(p_name text, p_occasion text, p_me text)
returns uuid language plpgsql security definer set search_path = public as $$
declare fid uuid; c text;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  loop
    select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '')
      into c from generate_series(1, 6);
    exit when not exists (select 1 from families where code = c);
  end loop;
  insert into families (name, occasion, code, created_by)
    values (trim(p_name), coalesce(trim(p_occasion), ''), c, auth.uid()) returning id into fid;
  insert into members (family_id, user_id) values (fid, auth.uid());
  insert into people (family_id, name, claimed_by) values (fid, trim(p_me), auth.uid());
  return fid;
end $$;

-- Join with a six-character code
create or replace function public.join_family(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  select id into fid from families where code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if fid is null then raise exception 'no_family'; end if;
  insert into members (family_id, user_id) values (fid, auth.uid()) on conflict do nothing;
  return fid;
end $$;

-- "That's me": link your account to an unclaimed name
create or replace function public.claim_person(p_person uuid)
returns void language plpgsql security definer set search_path = public as $$
declare fid uuid;
begin
  select family_id into fid from people where id = p_person;
  if fid is null or not is_member(fid) then raise exception 'no_person'; end if;
  if my_person(fid) is not null then raise exception 'already_claimed'; end if;
  update people set claimed_by = auth.uid() where id = p_person and claimed_by is null;
  if not found then raise exception 'taken'; end if;
end $$;

revoke execute on function public.create_family(text, text, text), public.join_family(text), public.claim_person(uuid) from public, anon;
grant  execute on function public.create_family(text, text, text), public.join_family(text), public.claim_person(uuid) to authenticated;

-- ---------- Live sync between phones ----------
alter publication supabase_realtime add table public.families, public.people, public.gifts;
