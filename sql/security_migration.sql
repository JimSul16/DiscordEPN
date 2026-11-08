-- ==============================================================================
-- DISCORD EPN - MIGRACIÓN DE SEGURIDAD Y REGLAS RLS
-- Generado a partir de AUDITORIA_BUGS_SEGURIDAD.md
-- ==============================================================================

begin;

-- ==============================================================================
-- 1. DIAGNÓSTICO Y LIMPIEZA PREVIA
-- ==============================================================================

-- 1.1 Limpieza de contenidos extensos o nulos
update public.messages
set content = left(content, 4000)
where content is not null and char_length(content) > 4000;

update public.profiles
set display_name = left(display_name, 32)
where char_length(display_name) > 32;

update public.profiles
set display_name = 'Usuario'
where char_length(display_name) < 3;

-- 1.2 Normalización de nombres de salas
update public.rooms
set name = lower(regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'));

update public.rooms
set name = 'canal-' || substr(id::text, 1, 8)
where name is null or name = '' or name !~ '^[a-z0-9][a-z0-9-]{1,31}$';

-- 1.3 Renombrar duplicados de lower(name) antes del índice único
with ranked as (
  select id, lower(name) as n,
         row_number() over (partition by lower(name) order by created_at, id) as rn
  from public.rooms
)
update public.rooms r
set name = left(r.name, 26) || '-' || substr(r.id::text, 1, 4)
from ranked
where r.id = ranked.id and ranked.rn > 1;

-- ==============================================================================
-- 2. HELPER DE IDENTIDAD (Firebase UID)
-- NOTA: auth.uid() devuelve UUID; Firebase emite texto (28 caracteres alfanuméricos).
-- ==============================================================================
create or replace function public.current_firebase_uid()
returns text
language sql
stable
security invoker
set search_path = ''
as $$
  select nullif(auth.jwt() ->> 'sub', '');
$$;

revoke all on function public.current_firebase_uid() from public;
grant execute on function public.current_firebase_uid() to authenticated, service_role;

-- ==============================================================================
-- 3. COLUMNAS DE OWNERSHIP Y AUDITORÍA
-- ==============================================================================
alter table public.profiles
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

alter table public.rooms
  add column if not exists created_by text references public.profiles(id) on delete set null,
  add column if not exists is_public boolean not null default true,
  add column if not exists updated_at timestamptz not null default now();

alter table public.messages
  add column if not exists updated_at timestamptz not null default now();

-- Tabla de membresías de salas
create table if not exists public.room_members (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  role text not null default 'member',
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

-- Denormalización de room_id en reacciones para Realtime y filtros
alter table public.message_reactions
  add column if not exists room_id uuid references public.rooms(id) on delete cascade;

-- Tabla de lecturas (read receipts)
create table if not exists public.message_reads (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id text not null references public.profiles(id) on delete cascade,
  room_id uuid references public.rooms(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Backfill de room_id en reacciones existentes
update public.message_reactions r
set room_id = m.room_id
from public.messages m
where r.message_id = m.id and r.room_id is null;

-- Tabla de tokens push (FCM) protegida
create table if not exists public.user_push_tokens (
  user_id text not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null check (platform in ('android','ios','web')),
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- ==============================================================================
-- 4. CONSTRAINTS DE INTEGRIDAD E ÍNDICES
-- ==============================================================================
-- Profiles
alter table public.profiles
  drop constraint if exists profiles_display_name_len,
  add constraint profiles_display_name_len check (char_length(display_name) between 3 and 32) not valid;

alter table public.profiles
  drop constraint if exists profiles_bio_len,
  add constraint profiles_bio_len check (bio is null or char_length(bio) <= 190) not valid;

-- Rooms
alter table public.rooms
  drop constraint if exists rooms_name_format,
  add constraint rooms_name_format check (name ~ '^[a-z0-9][a-z0-9-]{1,31}$') not valid;

-- Messages
alter table public.messages
  drop constraint if exists messages_content_len,
  add constraint messages_content_len check (content is null or char_length(content) <= 4000) not valid;

alter table public.messages
  drop constraint if exists messages_type_allowed,
  add constraint messages_type_allowed check (type in ('text','image','audio','location','file')) not valid;

alter table public.messages
  drop constraint if exists messages_text_has_content,
  add constraint messages_text_has_content check (
    type <> 'text' or (content is not null and btrim(content) <> '')
  ) not valid;

alter table public.messages
  drop constraint if exists messages_media_required,
  add constraint messages_media_required check (
    type not in ('image','file','audio') or media_url is not null
  ) not valid;

alter table public.messages
  drop constraint if exists messages_location_bounds,
  add constraint messages_location_bounds check (
    type <> 'location' or (
      latitude between -90 and 90 and
      longitude between -180 and 180
    )
  ) not valid;

-- Reactions
alter table public.message_reactions
  drop constraint if exists reactions_len,
  add constraint reactions_len check (char_length(reaction) between 1 and 32) not valid;

-- Miembros
alter table public.room_members
  drop constraint if exists room_members_role,
  add constraint room_members_role check (role in ('owner','admin','member')) not valid;

-- Validar constraints
alter table public.profiles validate constraint profiles_display_name_len;
alter table public.profiles validate constraint profiles_bio_len;
alter table public.rooms validate constraint rooms_name_format;
alter table public.messages validate constraint messages_content_len;
alter table public.messages validate constraint messages_type_allowed;
alter table public.messages validate constraint messages_text_has_content;
alter table public.messages validate constraint messages_media_required;
alter table public.messages validate constraint messages_location_bounds;
alter table public.message_reactions validate constraint reactions_len;
alter table public.room_members validate constraint room_members_role;

-- Índices de consulta rápida
create index if not exists messages_room_created_idx
  on public.messages (room_id, created_at desc, id desc);
create index if not exists messages_sender_idx
  on public.messages (sender_id);
create index if not exists reactions_message_idx
  on public.message_reactions (message_id);
create index if not exists reactions_user_idx
  on public.message_reactions (user_id);
create index if not exists reactions_room_idx
  on public.message_reactions (room_id);
create unique index if not exists message_reactions_msg_usr_react_uidx
  on public.message_reactions (message_id, user_id, reaction);
create index if not exists reads_user_idx
  on public.message_reads (user_id);
create index if not exists reads_room_idx
  on public.message_reads (room_id);
create index if not exists members_user_idx
  on public.room_members (user_id);
create index if not exists profiles_display_name_idx
  on public.profiles (lower(display_name));
create unique index if not exists rooms_name_lower_uidx
  on public.rooms (lower(name));

-- ==============================================================================
-- 5. TRIGGERS DE INTEGRIDAD
-- ==============================================================================
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists rooms_set_updated_at on public.rooms;
create trigger rooms_set_updated_at
before update on public.rooms
for each row execute function public.set_updated_at();

drop trigger if exists messages_set_updated_at on public.messages;
create trigger messages_set_updated_at
before update on public.messages
for each row execute function public.set_updated_at();

-- Forzar sender_id desde el JWT
create or replace function public.force_message_sender()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.sender_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.sender_id is distinct from old.sender_id then
    raise exception 'sender_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists messages_force_sender on public.messages;
create trigger messages_force_sender
before insert or update on public.messages
for each row execute function public.force_message_sender();

-- Forzar user_id en reacciones
create or replace function public.force_reaction_user()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.user_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.user_id is distinct from old.user_id then
    raise exception 'user_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists reactions_force_user on public.message_reactions;
create trigger reactions_force_user
before insert or update on public.message_reactions
for each row execute function public.force_reaction_user();

-- Forzar user_id en lecturas
create or replace function public.force_read_user()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.user_id := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.user_id is distinct from old.user_id then
    raise exception 'user_id es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists reads_force_user on public.message_reads;
create trigger reads_force_user
before insert or update on public.message_reads
for each row execute function public.force_read_user();

-- room_id derivado automáticamente del mensaje
create or replace function public.set_reaction_room()
returns trigger
language plpgsql
as $$
begin
  select room_id into new.room_id from public.messages where id = new.message_id;
  return new;
end;
$$;

drop trigger if exists reactions_set_room on public.message_reactions;
create trigger reactions_set_room
before insert or update of message_id on public.message_reactions
for each row execute function public.set_reaction_room();

create or replace function public.set_read_room()
returns trigger
language plpgsql
as $$
begin
  select room_id into new.room_id from public.messages where id = new.message_id;
  return new;
end;
$$;

drop trigger if exists reads_set_room on public.message_reads;
create trigger reads_set_room
before insert or update of message_id on public.message_reads
for each row execute function public.set_read_room();

-- Forzar created_by en salas
create or replace function public.force_room_creator()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'INSERT' and public.current_firebase_uid() is not null then
    new.created_by := public.current_firebase_uid();
  elsif tg_op = 'UPDATE' and new.created_by is distinct from old.created_by then
    raise exception 'created_by es inmutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_force_creator on public.rooms;
create trigger rooms_force_creator
before insert or update on public.rooms
for each row execute function public.force_room_creator();

-- El creador de la sala entra automáticamente como owner
create or replace function public.add_room_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.created_by is not null then
    insert into public.room_members(room_id, user_id, role)
    values (new.id, new.created_by, 'owner')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists rooms_add_owner on public.rooms;
create trigger rooms_add_owner
after insert on public.rooms
for each row execute function public.add_room_owner();

-- Revocar permisos de ejecución directa a PUBLIC sobre funciones trigger
revoke all on function public.set_updated_at() from public;
revoke all on function public.force_message_sender() from public;
revoke all on function public.force_reaction_user() from public;
revoke all on function public.force_read_user() from public;
revoke all on function public.set_reaction_room() from public;
revoke all on function public.set_read_room() from public;
revoke all on function public.force_room_creator() from public;
revoke all on function public.add_room_owner() from public;
grant execute on function public.add_room_owner() to service_role;

-- ==============================================================================
-- 6. POLÍTICAS RLS (Row Level Security)
-- ==============================================================================
create or replace function public.can_access_room(p_room_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.rooms r
    where r.id = p_room_id
      and (
        r.is_public = true
        or exists (
          select 1
          from public.room_members m
          where m.room_id = r.id
            and m.user_id = public.current_firebase_uid()
        )
      )
  );
$$;

revoke all on function public.can_access_room(uuid) from public;
grant execute on function public.can_access_room(uuid) to authenticated, service_role;

-- Habilitar RLS en todas las tablas
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_reactions enable row level security;
alter table public.message_reads enable row level security;
alter table public.user_push_tokens enable row level security;

-- Quitar accesos anónimos
revoke all on public.profiles, public.rooms, public.room_members,
  public.messages, public.message_reactions, public.message_reads,
  public.user_push_tokens
from anon;

-- Asegurar grants para el rol autenticado
grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.rooms to authenticated;
grant select, insert, update, delete on public.room_members to authenticated;
grant select, insert, update, delete on public.messages to authenticated;
grant select, insert, update, delete on public.message_reactions to authenticated;
grant select, insert, update, delete on public.message_reads to authenticated;
grant select, insert, update, delete on public.user_push_tokens to authenticated, service_role;

-- Limpieza de políticas previas
drop policy if exists profiles_select_authenticated on public.profiles;
drop policy if exists profiles_insert_self on public.profiles;
drop policy if exists profiles_update_self on public.profiles;
drop policy if exists rooms_select_accessible on public.rooms;
drop policy if exists rooms_insert_creator on public.rooms;
drop policy if exists rooms_update_creator on public.rooms;
drop policy if exists rooms_delete_creator on public.rooms;
drop policy if exists members_select_room on public.room_members;
drop policy if exists members_insert_owner on public.room_members;
drop policy if exists members_update_owner on public.room_members;
drop policy if exists members_delete_self_or_owner on public.room_members;
drop policy if exists messages_select_room on public.messages;
drop policy if exists messages_insert_room on public.messages;
drop policy if exists messages_update_own on public.messages;
drop policy if exists messages_delete_own on public.messages;
drop policy if exists reactions_select_room on public.message_reactions;
drop policy if exists reactions_insert_own on public.message_reactions;
drop policy if exists reactions_delete_own on public.message_reactions;
drop policy if exists reads_select_room on public.message_reads;
drop policy if exists reads_insert_own on public.message_reads;
drop policy if exists reads_update_own on public.message_reads;
drop policy if exists push_tokens_select_own on public.user_push_tokens;
drop policy if exists push_tokens_insert_own on public.user_push_tokens;
drop policy if exists push_tokens_update_own on public.user_push_tokens;
drop policy if exists push_tokens_delete_own on public.user_push_tokens;

-- PROFILES
create policy profiles_select_authenticated
on public.profiles for select
to authenticated
using (true);

create policy profiles_insert_self
on public.profiles for insert
to authenticated
with check (id = public.current_firebase_uid());

create policy profiles_update_self
on public.profiles for update
to authenticated
using (id = public.current_firebase_uid())
with check (id = public.current_firebase_uid());

-- ROOMS
create policy rooms_select_accessible
on public.rooms for select
to authenticated
using (public.can_access_room(id));

create policy rooms_insert_creator
on public.rooms for insert
to authenticated
with check (created_by = public.current_firebase_uid());

create policy rooms_update_creator
on public.rooms for update
to authenticated
using (created_by = public.current_firebase_uid())
with check (created_by = public.current_firebase_uid());

create policy rooms_delete_creator
on public.rooms for delete
to authenticated
using (created_by = public.current_firebase_uid());

-- ROOM MEMBERS
create policy members_select_room
on public.room_members for select
to authenticated
using (public.can_access_room(room_id));

create policy members_insert_owner
on public.room_members for insert
to authenticated
with check (
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

create policy members_update_owner
on public.room_members for update
to authenticated
using (
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
)
with check (
  exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

create policy members_delete_self_or_owner
on public.room_members for delete
to authenticated
using (
  user_id = public.current_firebase_uid()
  or exists (
    select 1 from public.rooms r
    where r.id = room_id
      and r.created_by = public.current_firebase_uid()
  )
);

-- MESSAGES
create policy messages_select_room
on public.messages for select
to authenticated
using (public.can_access_room(room_id));

create policy messages_insert_room
on public.messages for insert
to authenticated
with check (
  sender_id = public.current_firebase_uid()
  and public.can_access_room(room_id)
);

create policy messages_update_own
on public.messages for update
to authenticated
using (sender_id = public.current_firebase_uid())
with check (sender_id = public.current_firebase_uid());

create policy messages_delete_own
on public.messages for delete
to authenticated
using (sender_id = public.current_firebase_uid());

-- REACTIONS
create policy reactions_select_room
on public.message_reactions for select
to authenticated
using (
  exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reactions_insert_own
on public.message_reactions for insert
to authenticated
with check (
  user_id = public.current_firebase_uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reactions_delete_own
on public.message_reactions for delete
to authenticated
using (user_id = public.current_firebase_uid());

-- READS
create policy reads_select_room
on public.message_reads for select
to authenticated
using (
  user_id = public.current_firebase_uid()
  or exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reads_insert_own
on public.message_reads for insert
to authenticated
with check (
  user_id = public.current_firebase_uid()
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and public.can_access_room(m.room_id)
  )
);

create policy reads_update_own
on public.message_reads for update
to authenticated
using (user_id = public.current_firebase_uid())
with check (user_id = public.current_firebase_uid());

-- PUSH TOKENS
create policy push_tokens_select_own
on public.user_push_tokens for select
to authenticated
using (user_id = public.current_firebase_uid());

create policy push_tokens_insert_own
on public.user_push_tokens for insert
to authenticated
with check (user_id = public.current_firebase_uid());

create policy push_tokens_update_own
on public.user_push_tokens for update
to authenticated
using (user_id = public.current_firebase_uid())
with check (user_id = public.current_firebase_uid());

create policy push_tokens_delete_own
on public.user_push_tokens for delete
to authenticated
using (user_id = public.current_firebase_uid());

-- ==============================================================================
-- 7. RPCs ATÓMICAS
-- ==============================================================================
create or replace function public.create_room(p_name text)
returns public.rooms
language plpgsql
security invoker
set search_path = public
as $$
declare
  r public.rooms;
  clean text;
begin
  clean := lower(regexp_replace(trim(p_name), '[^a-zA-Z0-9]+', '-', 'g'));
  if clean !~ '^[a-z0-9][a-z0-9-]{1,31}$' then
    raise exception 'Nombre de canal inválido' using errcode = '22023';
  end if;

  insert into public.rooms(name, created_by)
  values (clean, public.current_firebase_uid())
  returning * into r;

  return r;
end;
$$;

grant execute on function public.create_room(text) to authenticated, service_role;

create or replace function public.toggle_reaction(p_message_id uuid, p_reaction text)
returns boolean
language plpgsql
security invoker
set search_path = public
as $$
declare
  removed int;
begin
  delete from public.message_reactions
  where message_id = p_message_id
    and user_id = public.current_firebase_uid()
    and reaction = p_reaction;

  get diagnostics removed = row_count;
  if removed > 0 then
    return false; -- se quitó
  end if;

  insert into public.message_reactions(message_id, user_id, reaction)
  values (p_message_id, public.current_firebase_uid(), p_reaction)
  on conflict do nothing;

  return true; -- se agregó
end;
$$;

grant execute on function public.toggle_reaction(uuid, text) to authenticated, service_role;

-- ==============================================================================
-- 8. REALTIME (Publicación y replica identity)
-- ==============================================================================
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'message_reactions'
  ) then
    alter publication supabase_realtime add table public.message_reactions;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'message_reads'
  ) then
    alter publication supabase_realtime add table public.message_reads;
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end $$;

alter table public.messages replica identity full;

commit;
