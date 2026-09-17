do $$
declare
  p record;
  v_using text;
  v_check text;
  v_sql text;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)'
            or coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)')
  loop
    v_using := regexp_replace(p.qual, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    v_check := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    v_sql := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if v_using is not null then v_sql := v_sql || ' using (' || v_using || ')'; end if;
    if v_check is not null then v_sql := v_sql || ' with check (' || v_check || ')'; end if;
    execute v_sql;
  end loop;
end;
$$;

do $$
declare r record;
begin
  for r in
    select c.conrelid::regclass as tbl, c.conname,
           (select string_agg(quote_ident(a.attname), ', ' order by k.n)
              from unnest(c.conkey) with ordinality k(attnum, n)
              join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum) as cols
      from pg_constraint c
      join pg_class t on t.oid = c.conrelid
      join pg_namespace ns on ns.oid = t.relnamespace
     where c.contype = 'f'
       and ns.nspname = 'public'
       and not exists (
         select 1 from pg_index i
          where i.indrelid = c.conrelid
            and (select array_agg(x) from unnest((i.indkey::int2[])[0:cardinality(c.conkey) - 1]) x)
                = c.conkey::int2[])
  loop
    execute format('create index if not exists %I on %s (%s)', left('fk_' || r.conname, 63), r.tbl, r.cols);
  end loop;
end;
$$;

create table if not exists omelo_private.app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
revoke all on omelo_private.app_settings from public, anon, authenticated;

insert into omelo_private.app_settings (key, value)
values ('functions_base_url', 'https://jfyqnlucoraazjkndbvm.supabase.co/functions/v1')
on conflict (key) do nothing;

create or replace function omelo_private.omelo_dispatch_comms()
returns bigint
language plpgsql security definer
set search_path = public, omelo_private, extensions
as $$
declare v_base text;
begin
  select value into v_base from omelo_private.app_settings where key = 'functions_base_url';
  if v_base is null then
    return null;
  end if;
  return net.http_post(
    url := rtrim(v_base, '/') || '/comms-dispatch',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb,
    timeout_milliseconds := 30000);
end;
$$;
revoke execute on function omelo_private.omelo_dispatch_comms() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job where jobname = 'omelo-comms-dispatch';
select cron.schedule('omelo-comms-dispatch', '* * * * *', $$ select omelo_private.omelo_dispatch_comms() $$);