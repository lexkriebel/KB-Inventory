-- =====================================================================
--  Royaltea Bar sign-up sheet — Supabase setup
--  Run AFTER supabase-setup.sql (it uses the same "editors" list).
--  Paste into Supabase → SQL Editor → New query → Run. Safe to run again.
-- =====================================================================

-- ---------- 1. Tables -------------------------------------------------
-- What the bar needs. Editors can change this list on the page.
create table if not exists public.bar_items (
  id         bigint generated always as identity primary key,
  name       text    not null check (length(trim(name)) between 1 and 120),
  needed     integer not null default 1 check (needed >= 0),
  packaging  text    not null default '' check (length(packaging) <= 80),
  sort       integer not null default 0,
  created_at timestamptz not null default now()
);

-- Who is bringing what. Character names are public.
create table if not exists public.bar_signups (
  id             bigint generated always as identity primary key,
  item_id        bigint  not null references public.bar_items(id) on delete cascade,
  character_name text    not null check (length(trim(character_name)) between 1 and 80),
  qty            integer not null check (qty > 0),
  created_at     timestamptz not null default now()
);
create index if not exists bar_signups_item_idx on public.bar_signups (item_id);

-- Real names, kept separate so only editors can see them.
create table if not exists public.bar_signup_private (
  signup_id bigint primary key references public.bar_signups(id) on delete cascade,
  real_name text not null check (length(trim(real_name)) between 1 and 80)
);

-- ---------- 2. Security -------------------------------------------------
alter table public.bar_items          enable row level security;
alter table public.bar_signups        enable row level security;
alter table public.bar_signup_private enable row level security;

drop policy if exists "Anyone can read bar items" on public.bar_items;
create policy "Anyone can read bar items" on public.bar_items
  for select to anon, authenticated using (true);
drop policy if exists "Anyone can read bar signups" on public.bar_signups;
create policy "Anyone can read bar signups" on public.bar_signups
  for select to anon, authenticated using (true);
-- (No policies on bar_signup_private: real names are only reachable
--  through bar_admin_signups(), which checks the editors list.)

revoke all on public.bar_items, public.bar_signups, public.bar_signup_private from anon, authenticated;
grant select on public.bar_items, public.bar_signups to anon, authenticated;

-- ---------- 3. Signing up (anyone) --------------------------------------
-- p_items is a list like [{"item_id": 4, "qty": 1}, ...]. Everything is saved
-- together or not at all, and nobody can sign up for more than is still needed.
create or replace function public.bar_sign_up(p_real_name text, p_character text, p_items jsonb)
returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
declare r record; v_needed integer; v_taken integer; v_name text; v_id bigint; v_n integer := 0;
begin
  if length(trim(coalesce(p_real_name, ''))) not between 1 and 80 then raise exception 'bad_real_name'; end if;
  if length(trim(coalesce(p_character, ''))) not between 1 and 80 then raise exception 'bad_character'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 60 then
    raise exception 'bad_items';
  end if;
  for r in select (x ->> 'item_id')::bigint as item_id, (x ->> 'qty')::integer as qty
             from jsonb_array_elements(p_items) x order by 1 loop
    if r.qty is null or r.qty < 1 then raise exception 'bad_qty'; end if;
    select needed, name into v_needed, v_name from public.bar_items where id = r.item_id for update;
    if not found then raise exception 'item_missing'; end if;
    select coalesce(sum(qty), 0) into v_taken from public.bar_signups where item_id = r.item_id;
    if r.qty > v_needed - v_taken then
      raise exception 'too_many: % only needs % more', v_name, greatest(v_needed - v_taken, 0);
    end if;
    insert into public.bar_signups (item_id, character_name, qty)
      values (r.item_id, trim(p_character), r.qty) returning id into v_id;
    insert into public.bar_signup_private (signup_id, real_name) values (v_id, trim(p_real_name));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

-- ---------- 4. Editor tools -----------------------------------------------
-- Sign-ups including real names (editors only).
create or replace function public.bar_admin_signups()
returns table (id bigint, item_id bigint, character_name text, real_name text, qty integer, created_at timestamptz)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  perform public._require_editor();
  return query select s.id, s.item_id, s.character_name, p.real_name, s.qty, s.created_at
    from public.bar_signups s left join public.bar_signup_private p on p.signup_id = s.id
    order by s.id;
end $$;

-- Change a sign-up. A quantity of 0 removes it.
create or replace function public.bar_edit_signup(p_id bigint, p_character text, p_real_name text, p_qty integer)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  perform public._require_editor();
  if coalesce(p_qty, 0) <= 0 then delete from public.bar_signups where id = p_id; return; end if;
  update public.bar_signups set character_name = trim(p_character), qty = p_qty where id = p_id;
  insert into public.bar_signup_private (signup_id, real_name) values (p_id, trim(p_real_name))
    on conflict (signup_id) do update set real_name = excluded.real_name;
end $$;

create or replace function public.bar_delete_signup(p_id bigint)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  perform public._require_editor();
  delete from public.bar_signups where id = p_id;
end $$;

-- Start a fresh sheet (keeps the item list).
create or replace function public.bar_clear_signups()
returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
declare v integer;
begin
  perform public._require_editor();
  delete from public.bar_signups where true;
  get diagnostics v = row_count;
  return v;
end $$;

-- Add (p_id null) or change an item.
create or replace function public.bar_save_item(p_id bigint, p_name text, p_needed integer, p_packaging text)
returns bigint language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_id bigint;
begin
  perform public._require_editor();
  if p_id is null then
    insert into public.bar_items (name, needed, packaging, sort)
      values (trim(p_name), greatest(coalesce(p_needed, 1), 0), coalesce(trim(p_packaging), ''),
              coalesce((select max(sort) from public.bar_items), 0) + 10)
      returning id into v_id;
  else
    update public.bar_items set name = trim(p_name), needed = greatest(coalesce(p_needed, 1), 0),
      packaging = coalesce(trim(p_packaging), '') where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;

-- Remove an item (and its sign-ups).
create or replace function public.bar_delete_item(p_id bigint)
returns void language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  perform public._require_editor();
  delete from public.bar_items where id = p_id;
end $$;

revoke execute on function public.bar_sign_up(text, text, jsonb), public.bar_admin_signups(),
  public.bar_edit_signup(bigint, text, text, integer), public.bar_delete_signup(bigint),
  public.bar_clear_signups(), public.bar_save_item(bigint, text, integer, text),
  public.bar_delete_item(bigint) from public, anon, authenticated;
grant execute on function public.bar_sign_up(text, text, jsonb) to anon, authenticated;
grant execute on function public.bar_admin_signups(), public.bar_edit_signup(bigint, text, text, integer),
  public.bar_delete_signup(bigint), public.bar_clear_signups(),
  public.bar_save_item(bigint, text, integer, text), public.bar_delete_item(bigint) to authenticated;

-- ---------- 5. Live updates -------------------------------------------------
do $$ begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                 and schemaname = 'public' and tablename = 'bar_items') then
    alter publication supabase_realtime add table public.bar_items;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime'
                 and schemaname = 'public' and tablename = 'bar_signups') then
    alter publication supabase_realtime add table public.bar_signups;
  end if;
end $$;

-- ---------- 6. The sign-up items (only added if the list is empty) -----------
insert into public.bar_items (name, needed, packaging, sort)
select v.name, v.needed, v.packaging, v.sort from (values
  ('Dew of the Mountain', 1, '12pk can', 10),
  ('Dwarven Ale', 1, '12pk can', 20),
  ('Ale', 1, '12pk can', 30),
  ('FOW Ale', 3, '12pk can', 40),
  ('Lite Ale', 1, '12pk can', 50),
  ('Ginger Beer', 1, '12pk can', 60),
  ('Sea Foam Spirits', 1, '12pk can', 70),
  ('Fae Wine', 1, '12pk can', 80),
  ('Fuzzy Water', 4, '12pk can', 90),
  ('Coffee', 3, '12pk K cup', 100),
  ('Hot Coco', 1, '12pk K cup/Pack', 110),
  ('Hot Tea', 2, '1 box', 120),
  ('Monsterous Brew', 1, '12pk can', 130),
  ('Bull''s Blood', 1, '12pk can', 140),
  ('Celestial Brew', 1, '12pk can', 150),
  ('Barrels', 1, '1cs', 160),
  ('Boo Juice', 2, '12pk box', 170),
  ('Muffins', 24, 'each', 180),
  ('Cookies', 24, 'each', 190),
  ('Cup O Soup', 24, 'each', 200),
  ('Chips', 1, '28 ea bag', 210),
  ('Pickles', 2, '1 jars', 220),
  ('Moo Mix', 2, 'bags', 230),
  ('Paper Cups', 1, '20ct sleeve', 240),
  ('Coffee Cups', 1, '20ct sleeve', 250),
  ('Plastic Forks', 1, '50ct box', 260),
  ('Plastic Spoons', 1, '50ct box', 270),
  ('Plastic Knives', 1, '20ct box', 280),
  ('Napkins', 1, '100ct pack', 290),
  ('Paper Towels', 1, 'roll', 300)
) as v(name, needed, packaging, sort)
where not exists (select 1 from public.bar_items);

select count(*) as bar_items from public.bar_items;
