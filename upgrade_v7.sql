-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v7  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql, fix_txn_edits.sql, upgrade_v2.sql–v4.sql, upgrade_v5.sql มาก่อนแล้ว
-- รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   1. แก้ log_txn_edit() — upgrade_v5.sql เขียนฟังก์ชันนี้ใหม่ทับเพื่อเพิ่มการติดตาม to_who
--      แต่ไปอิงจากเวอร์ชันก่อน upgrade_v4.sql ทำให้บรรทัดติดตาม "เปลี่ยนสลิป" หายไปด้วย
--      (ใครที่รัน upgrade_v5.sql ไปแล้ว การเปลี่ยน/แนบสลิปใหม่จะไม่ขึ้นในประวัติการแก้ไขอีกเลย
--      จนกว่าจะรันไฟล์นี้) ข้อนี้แก้โดยรวมทั้งสองอย่างกลับเข้าฟังก์ชันเดียวกัน
--   2. ตาราง year_goal — เป้าเงินเก็บทั้งปี ย้ายจาก config.js มาเก็บในฐานข้อมูลจริง
--      แก้ได้จากหน้า "ตั้งค่า" เหมือน budgets แต่เป็นแถวเดียวตายตัว (id = 1 เสมอ)
-- ─────────────────────────────────────────────────────────────


-- ═══ 1. แก้ log_txn_edit() — ติดตามครบทั้ง slip และ to_who ═══════

create or replace function public.log_txn_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare ch jsonb := '[]'::jsonb;
begin
  if new.ts        is distinct from old.ts        then ch := ch || jsonb_build_object('field','ts',       'from', old.ts::text,      'to', new.ts::text);      end if;
  if new.name      is distinct from old.name      then ch := ch || jsonb_build_object('field','name',     'from', old.name,          'to', new.name);          end if;
  if new.cat       is distinct from old.cat       then ch := ch || jsonb_build_object('field','cat',      'from', old.cat,           'to', new.cat);           end if;
  if new.method    is distinct from old.method    then ch := ch || jsonb_build_object('field','method',   'from', old.method,        'to', new.method);        end if;
  if new.method_to is distinct from old.method_to then ch := ch || jsonb_build_object('field','method_to','from', old.method_to,     'to', new.method_to);     end if;
  if new.to_who    is distinct from old.to_who    then ch := ch || jsonb_build_object('field','to_who',   'from', old.to_who,        'to', new.to_who);        end if;
  if new.kind      is distinct from old.kind      then ch := ch || jsonb_build_object('field','kind',     'from', old.kind,          'to', new.kind);          end if;
  if new.amt       is distinct from old.amt       then ch := ch || jsonb_build_object('field','amt',      'from', old.amt::text,     'to', new.amt::text);     end if;
  if new.code      is distinct from old.code      then ch := ch || jsonb_build_object('field','code',     'from', old.code,          'to', new.code);          end if;
  if new.flag      is distinct from old.flag      then ch := ch || jsonb_build_object('field','flag',     'from', old.flag,          'to', new.flag);          end if;
  if new.who       is distinct from old.who       then ch := ch || jsonb_build_object('field','who',      'from', old.who,           'to', new.who);           end if;
  if new.slip      is distinct from old.slip      then ch := ch || jsonb_build_object('field','slip',     'from', old.slip,          'to', new.slip);          end if;
  if new.void_at   is distinct from old.void_at   then ch := ch || jsonb_build_object('field','void',
    'from', case when old.void_at is null then '' else 'ยกเลิก · ' || old.void_reason end,
    'to',   case when new.void_at is null then '' else 'ยกเลิก · ' || btrim(new.void_reason) end); end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;


-- ═══ 2. เป้าเงินเก็บทั้งปี ══════════════════════════════════════
-- แถวเดียวตายตัว (id = 1) — ไม่ใช่ list เหมือน budgets เพราะมีค่าเดียวทั้งสมุด

create table if not exists public.year_goal (
  id     int primary key default 1,
  amount numeric not null default 0 check (amount >= 0),
  code   text not null default 'KIP',
  constraint year_goal_singleton check (id = 1)
);

alter table public.year_goal enable row level security;

drop policy if exists year_goal_read   on public.year_goal;
drop policy if exists year_goal_write  on public.year_goal;
drop policy if exists year_goal_update on public.year_goal;

-- ทุกคนที่ล็อกอินอ่านได้ · แก้ได้เฉพาะบัญชีหลัก (ไม่มี policy delete — แถวตั้งต้นลบไม่ได้)
create policy year_goal_read   on public.year_goal for select to authenticated using (true);
create policy year_goal_write  on public.year_goal for insert to authenticated with check (public.is_admin());
create policy year_goal_update on public.year_goal for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.year_goal from anon;

-- ยกค่าเดิมจาก config.js มาตั้งต้น — ครั้งเดียว ถ้ายังไม่มีแถว
insert into public.year_goal (id, amount, code) values (1, 60000000, 'KIP')
on conflict (id) do nothing;


-- ═══ บอก PostgREST ให้โหลด schema ใหม่ ════════════════════════

notify pgrst, 'reload schema';


-- ═══ ตรวจผล ═══════════════════════════════════════════════════

select exists (select 1 from pg_proc
                where proname = 'log_txn_edit'
                  and pg_get_functiondef(oid) like '%''field'',''slip''%'
                  and pg_get_functiondef(oid) like '%''field'',''to_who''%')  as "log_txn_edit ติดตามครบ slip+to_who",
       (select count(*) from public.year_goal)                               as "แถว year_goal (ควรเป็น 1)",
       (select count(*) from pg_policies where tablename = 'year_goal')      as "policy ของ year_goal (ควรเป็น 3)";
