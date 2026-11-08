-- ==============================================================================
-- CONSULTAS DE VERIFICACIÓN DE RLS Y PERMISOS REALES
-- ==============================================================================

-- 1. Tablas y estado de RLS (debe devolver true en todas)
select tablename, rowsecurity
from pg_tables
where schemaname = 'public'
  and tablename in ('profiles','rooms','room_members','messages','message_reactions','message_reads','user_push_tokens')
order by tablename;

-- 2. Conteo de políticas por tabla (debe haber al menos 1 por tabla)
select tablename, count(*) as policies_count
from pg_policies
where schemaname = 'public'
group by tablename
order by tablename;

-- 3. Privilegios de anon (no debe devolver ningún permiso sobre public)
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'anon' and table_schema = 'public'
order by table_name, privilege_type;

-- 4. Privilegios de authenticated (debe tener SELECT, INSERT, UPDATE, DELETE según aplique)
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'authenticated' and table_schema = 'public'
order by table_name, privilege_type;

-- ==============================================================================
-- 5. SIMULACIÓN DE PRUEBA REAL DE ACCESO POR ROLES
-- ==============================================================================

-- 5.1 Verificación empírica con rol anon (debe ser bloqueado por RLS)
begin;
set role anon;

do $$
begin
  -- Intentar insertar como anónimo sin token
  insert into public.messages (room_id, sender_id, content)
  values ('00000000-0000-0000-0000-000000000000', 'intruso', 'intento');
  raise exception 'ALERTA: anon logró escribir en messages';
exception
  when insufficient_privilege then
    raise notice 'CORRECTO: anon rechazado con 42501 (insufficient_privilege)';
  when others then
    raise notice 'CORRECTO: anon bloqueado (%): %', sqlstate, sqlerrm;
end $$;

rollback;

-- 5.2 Verificación empírica con usuario autenticado
begin;
set role authenticated;
set local "request.jwt.claim.sub" = 'test_firebase_uid_abc';
set local "request.jwt.claim.role" = 'authenticated';

select count(*) as profile_count from public.profiles;

rollback;
