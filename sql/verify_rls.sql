-- ==============================================================================
-- CONSULTAS DE VERIFICACIÓN DE RLS Y PERMISOS
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
