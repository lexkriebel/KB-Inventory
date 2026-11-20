-- =====================================================================
--  Quartermaster's Inventory — Supabase setup
--  Paste this whole file into Supabase → SQL Editor → New query → Run.
--  It is safe to run more than once: it never overwrites existing counts.
-- =====================================================================

-- ---------- 1. Tables -------------------------------------------------

-- One row per inventory item. "version" goes up on every change so the
-- page can tell newer information from older.
create sequence if not exists public.items_version_seq;

create table if not exists public.items (
  name       text primary key check (length(trim(name)) between 1 and 200),
  category   text not null default 'Misc' check (category in (
               'Weapon/Tool/Armor','Animal/Fleshy/Bone','Sealife','Bug','Plant',
               'Metal/Stone','Gems','Money','Potions/Poison/Oils','Scroll',
               'Item of Quality','Misc')),
  qty        integer not null default 0 check (qty >= 0),
  version    bigint  not null default nextval('public.items_version_seq'),
  updated_at timestamptz not null default now()
);

-- The people allowed to make changes. Add or remove rows here
-- (Table Editor → editors) to add or remove editors.
create table if not exists public.editors (
  email    text primary key,
  name     text,              -- optional: shown in "Recent changes"
  added_at timestamptz not null default now()
);

-- Every change: who, which item, old → new, when.
create table if not exists public.change_log (
  id         bigint generated always as identity primary key,
  item_name  text not null,
  old_qty    integer,          -- empty for a newly added item
  new_qty    integer,          -- empty for a removed item
  action     text not null,    -- adjust, set, add, remove, import
  who        text not null,    -- editor's name (or the start of their email)
  email      text,             -- full email: visible to you in the dashboard only
  user_id    uuid,
  created_at timestamptz not null default now()
);
create index if not exists change_log_created_idx on public.change_log (created_at desc);

-- ---------- 2. Row Level Security -----------------------------------
-- Everyone (even not signed in) may READ items and the change log.
-- Nobody may write to the tables directly; all changes go through the
-- functions below, which check the editors list first.

alter table public.items      enable row level security;
alter table public.editors    enable row level security;
alter table public.change_log enable row level security;

drop policy if exists "Anyone can read items" on public.items;
create policy "Anyone can read items" on public.items
  for select to anon, authenticated using (true);

drop policy if exists "Anyone can read the change log" on public.change_log;
create policy "Anyone can read the change log" on public.change_log
  for select to anon, authenticated using (true);
-- (No policies on "editors": the list is not readable from the web page.)

grant usage on schema public to anon, authenticated;
revoke all on public.items, public.editors, public.change_log from anon, authenticated;
grant select on public.items to anon, authenticated;
-- The public may see the log, but not the "email" or "user_id" columns.
grant select (id, item_name, old_qty, new_qty, action, who, created_at)
  on public.change_log to anon, authenticated;

-- ---------- 3. Helper functions -------------------------------------

-- Is the signed-in person on the editors list?
create or replace function public.is_editor()
returns boolean language sql stable security definer
set search_path = public, pg_temp as $$
  select auth.uid() is not null and exists (
    select 1 from public.editors e
    where lower(trim(e.email)) = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;

create or replace function public._require_editor()
returns void language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  if not public.is_editor() then
    raise exception 'not_editor: you are not on the editors list' using errcode = '42501';
  end if;
end $$;

create or replace function public._editor_name()
returns text language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce(
    (select nullif(trim(e.name), '') from public.editors e
      where lower(trim(e.email)) = lower(auth.jwt() ->> 'email') limit 1),
    split_part(coalesce(auth.jwt() ->> 'email', 'unknown'), '@', 1));
$$;

create or replace function public._log(p_item text, p_old integer, p_new integer, p_action text)
returns void language sql security definer
set search_path = public, pg_temp as $$
  insert into public.change_log (item_name, old_qty, new_qty, action, who, email, user_id)
  values (p_item, p_old, p_new, p_action, public._editor_name(), auth.jwt() ->> 'email', auth.uid());
$$;

-- Lets the page ask "am I an editor, and what's my name?"
create or replace function public.whoami()
returns jsonb language sql stable security definer
set search_path = public, pg_temp as $$
  select jsonb_build_object('editor', public.is_editor(), 'name', public._editor_name());
$$;

-- ---------- 4. Functions the page calls to make changes ---------------
-- Each one locks only the item it changes, so many people can edit at once.

-- Add or subtract (the − / + buttons). Never goes below 0.
create or replace function public.adjust_qty(p_name text, p_delta integer, p_category text default null)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_old integer; v_new integer; v_ver bigint;
begin
  perform public._require_editor();
  if p_delta is null or abs(p_delta) > 1000000 then raise exception 'bad amount'; end if;
  insert into public.items (name, category) values (trim(p_name), coalesce(p_category, 'Misc'))
    on conflict (name) do nothing;
  select qty, version into v_old, v_ver from public.items where name = trim(p_name) for update;
  v_new := greatest(0, v_old + p_delta);
  if v_new <> v_old then
    update public.items set qty = v_new, version = nextval('public.items_version_seq'), updated_at = now()
      where name = trim(p_name) returning version into v_ver;
    perform public._log(trim(p_name), v_old, v_new, 'adjust');
  end if;
  return jsonb_build_object('name', trim(p_name), 'qty', v_new, 'old', v_old, 'version', v_ver);
end $$;

-- Set an exact number (typing in the box).
create or replace function public.set_qty(p_name text, p_qty integer, p_category text default null)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_old integer; v_new integer := greatest(0, coalesce(p_qty, 0)); v_ver bigint;
begin
  perform public._require_editor();
  insert into public.items (name, category) values (trim(p_name), coalesce(p_category, 'Misc'))
    on conflict (name) do nothing;
  select qty, version into v_old, v_ver from public.items where name = trim(p_name) for update;
  if v_new <> v_old then
    update public.items set qty = v_new, version = nextval('public.items_version_seq'), updated_at = now()
      where name = trim(p_name) returning version into v_ver;
    perform public._log(trim(p_name), v_old, v_new, 'set');
  end if;
  return jsonb_build_object('name', trim(p_name), 'qty', v_new, 'old', v_old, 'version', v_ver);
end $$;

-- Add a custom item.
create or replace function public.add_item(p_name text, p_category text, p_qty integer default 0)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_ver bigint; v_q integer := greatest(0, coalesce(p_qty, 0));
begin
  perform public._require_editor();
  if exists (select 1 from public.items where lower(name) = lower(trim(p_name))) then
    raise exception 'exists: that item is already in the list';
  end if;
  insert into public.items (name, category, qty) values (trim(p_name), coalesce(p_category, 'Misc'), v_q)
    returning version into v_ver;
  perform public._log(trim(p_name), null, v_q, 'add');
  return jsonb_build_object('name', trim(p_name), 'category', coalesce(p_category, 'Misc'),
                            'qty', v_q, 'old', 0, 'version', v_ver);
end $$;

-- Remove a custom item.
create or replace function public.remove_item(p_name text)
returns jsonb language plpgsql security definer
set search_path = public, pg_temp as $$
declare v_old integer; v_cat text;
begin
  perform public._require_editor();
  delete from public.items where name = p_name returning qty, category into v_old, v_cat;
  if found then perform public._log(p_name, v_old, null, 'remove'); end if;
  return jsonb_build_object('name', p_name, 'old', v_old, 'category', v_cat);
end $$;

-- Replace the whole inventory (the page's Import button and the one-time
-- inventory.json import). p_items is a list of {name, category, qty}.
-- Items not in the list are set to 0.
create or replace function public.import_inventory(p_items jsonb)
returns integer language plpgsql security definer
set search_path = public, pg_temp as $$
declare r record; v_old integer; v_changes integer := 0; v_names text[] := '{}';
begin
  perform public._require_editor();
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'import list is empty';
  end if;
  for r in select trim(x ->> 'name') as name,
                  coalesce(nullif(x ->> 'category', ''), 'Misc') as category,
                  greatest(0, coalesce((x ->> 'qty')::integer, 0)) as qty
             from jsonb_array_elements(p_items) x
            where coalesce(trim(x ->> 'name'), '') <> ''
  loop
    v_names := v_names || r.name;
    select qty into v_old from public.items where name = r.name for update;
    if not found then
      insert into public.items (name, category, qty) values (r.name, r.category, r.qty);
      perform public._log(r.name, null, r.qty, 'import');
      v_changes := v_changes + 1;
    elsif v_old <> r.qty then
      update public.items set qty = r.qty, version = nextval('public.items_version_seq'), updated_at = now()
        where name = r.name;
      perform public._log(r.name, v_old, r.qty, 'import');
      v_changes := v_changes + 1;
    end if;
  end loop;
  -- Anything not in the list is set to 0 (never deleted, so nothing is lost).
  for r in select name, qty from public.items
            where not (name = any (v_names)) and qty <> 0 for update loop
    update public.items set qty = 0, version = nextval('public.items_version_seq'), updated_at = now()
      where name = r.name;
    perform public._log(r.name, r.qty, 0, 'import');
    v_changes := v_changes + 1;
  end loop;
  return v_changes;
end $$;

-- Who may run which function: helpers are internal; change functions need
-- a signed-in user (and then check the editors list themselves).
revoke execute on function public.is_editor(), public._require_editor(), public._editor_name(),
  public._log(text, integer, integer, text), public.whoami(),
  public.adjust_qty(text, integer, text), public.set_qty(text, integer, text),
  public.add_item(text, text, integer), public.remove_item(text),
  public.import_inventory(jsonb)
  from public, anon, authenticated;
grant execute on function public.whoami(), public.is_editor() to anon, authenticated;
grant execute on function public.adjust_qty(text, integer, text), public.set_qty(text, integer, text),
  public.add_item(text, text, integer), public.remove_item(text),
  public.import_inventory(jsonb) to authenticated;

-- ---------- 5. Live updates (Realtime) --------------------------------
do $$ begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'items') then
    alter publication supabase_realtime add table public.items;
  end if;
end $$;

-- ---------- 6. Starting items and your current counts -----------------
-- All 93 standard items, with the counts from inventory.json as of 2026-11-20.
-- "on conflict do nothing" means running this again won't reset any counts.
insert into public.items (name, category, qty) values
  ('Archery Weapon', 'Weapon/Tool/Armor', 1),
  ('Armor - Heavy', 'Weapon/Tool/Armor', 1),
  ('Armor - Light', 'Weapon/Tool/Armor', 1),
  ('Armor - Moderate', 'Weapon/Tool/Armor', 1),
  ('Fishing Rod', 'Weapon/Tool/Armor', 0),
  ('One Handed Weapon', 'Weapon/Tool/Armor', 0),
  ('One Handed Weapon - Small', 'Weapon/Tool/Armor', 0),
  ('Pickaxe', 'Weapon/Tool/Armor', 0),
  ('Shield', 'Weapon/Tool/Armor', 0),
  ('Throwing Weapon', 'Weapon/Tool/Armor', 0),
  ('Two Handed Weapon', 'Weapon/Tool/Armor', 0),
  ('Bat Fat', 'Animal/Fleshy/Bone', 0),
  ('Bat Hide', 'Animal/Fleshy/Bone', 0),
  ('Bat Meat', 'Animal/Fleshy/Bone', 0),
  ('Bones', 'Animal/Fleshy/Bone', 0),
  ('Cockatrice Feather', 'Animal/Fleshy/Bone', 0),
  ('Dark Elf Fat', 'Animal/Fleshy/Bone', 0),
  ('Dark Elf Meat', 'Animal/Fleshy/Bone', 0),
  ('Dark Elf Skin', 'Animal/Fleshy/Bone', 0),
  ('Deep Gnome Hide', 'Animal/Fleshy/Bone', 0),
  ('Deep Gnome Fat', 'Animal/Fleshy/Bone', 0),
  ('Deep Gnome Meat', 'Animal/Fleshy/Bone', 0),
  ('Giant Fat', 'Animal/Fleshy/Bone', 0),
  ('Giant Hide', 'Animal/Fleshy/Bone', 0),
  ('Giant Meat', 'Animal/Fleshy/Bone', 0),
  ('Human Skin', 'Animal/Fleshy/Bone', 0),
  ('Human Teeth', 'Animal/Fleshy/Bone', 0),
  ('Nekros Bones', 'Animal/Fleshy/Bone', 0),
  ('Shadow Elf Skin', 'Animal/Fleshy/Bone', 0),
  ('Shadow Elf Fat', 'Animal/Fleshy/Bone', 0),
  ('Shadow Elf Meat', 'Animal/Fleshy/Bone', 0),
  ('Spider Fat', 'Animal/Fleshy/Bone', 0),
  ('Spider Meat', 'Animal/Fleshy/Bone', 0),
  ('Troll Fat', 'Animal/Fleshy/Bone', 0),
  ('Troll Hide', 'Animal/Fleshy/Bone', 0),
  ('Troll Meat', 'Animal/Fleshy/Bone', 0),
  ('Blue Bass', 'Sealife', 0),
  ('Green Bass', 'Sealife', 0),
  ('Blue Fish', 'Sealife', 0),
  ('Green Fish', 'Sealife', 0),
  ('Crab', 'Sealife', 0),
  ('Drezzil Fish', 'Sealife', 0),
  ('Large fish', 'Sealife', 0),
  ('Little Fish', 'Sealife', 0),
  ('Minnow', 'Sealife', 0),
  ('Maggot', 'Bug', 0),
  ('Small Spider', 'Bug', 0),
  ('Spider Silk', 'Bug', 0),
  ('Worm', 'Bug', 0),
  ('Green Plant', 'Plant', 0),
  ('Green Plant Seed', 'Plant', 0),
  ('Purple Flowers', 'Plant', 0),
  ('Seaweed', 'Plant', 0),
  ('Sunflower', 'Plant', 0),
  ('Wheat', 'Plant', 0),
  ('Wheat Seed', 'Plant', 0),
  ('Wood', 'Plant', 0),
  ('Green Flower', 'Plant', 0),
  ('Wheat Flower', 'Plant', 0),
  ('Copper Ore', 'Metal/Stone', 0),
  ('Gold Ore', 'Metal/Stone', 0),
  ('Iron Ore', 'Metal/Stone', 0),
  ('Silver Ore', 'Metal/Stone', 0),
  ('Blue Gem', 'Gems', 0),
  ('Clear Gem', 'Gems', 0),
  ('Green Gem', 'Gems', 0),
  ('Purple Gem', 'Gems', 0),
  ('Red Gem', 'Gems', 0),
  ('Yellow Gem', 'Gems', 0),
  ('Gold', 'Money', 0),
  ('Silver', 'Money', 0),
  ('Jade', 'Money', 0),
  ('Cure Minor', 'Potions/Poison/Oils', 0),
  ('Cure Mortal', 'Potions/Poison/Oils', 0),
  ('Flaming Oil', 'Potions/Poison/Oils', 0),
  ('Limited Restoration', 'Potions/Poison/Oils', 0),
  ('Oil', 'Potions/Poison/Oils', 0),
  ('Ruggedness Potion', 'Potions/Poison/Oils', 0),
  ('Silver Oils', 'Potions/Poison/Oils', 0),
  ('Spell Guard Potion', 'Potions/Poison/Oils', 0),
  ('Poison 20', 'Potions/Poison/Oils', 0),
  ('Poison 50', 'Potions/Poison/Oils', 0),
  ('Enchanted Weapon Scroll', 'Scroll', 0),
  ('Ravenger Holy Symbol #0522 (blue markings)', 'Item of Quality', 0),
  ('Scrying Mirror #0995', 'Item of Quality', 0),
  ('Yellow Gem Socketed Ring', 'Item of Quality', 0),
  ('Silver Necklace', 'Item of Quality', 0),
  ('Black Spider Flowers', 'Misc', 0),
  ('Death Token', 'Misc', 0),
  ('Holy Water', 'Misc', 0),
  ('Wax', 'Misc', 0),
  ('Evil Mirror', 'Misc', 0),
  ('Manacles', 'Misc', 0)
on conflict (name) do nothing;

-- ---------- 7. Your first editor ---------------------------------------
-- Optional: replace the email and name below, remove the two dashes at the
-- start of the next line, and run again. (Or add yourself in Table Editor.)
-- insert into public.editors (email, name) values ('you@example.com', 'Your name') on conflict do nothing;
