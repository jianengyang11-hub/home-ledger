-- ─────────────────────────────────────────────────────────────
-- แก้เฉพาะเรื่องประวัติการแก้ไข (ตาราง txn_edits)
--
-- วิธีใช้: Supabase → SQL Editor → Ctrl+A เลือกทั้งไฟล์นี้ → วาง → กด Run
-- อย่าลากเลือกแค่บางส่วน เพราะ Supabase จะรันเฉพาะที่ไฮไลต์ไว้
--
-- ตรวจก่อนว่า URL ของหน้า SQL Editor มีคำว่า xhnuigcwbcycthqjgjzb
-- (ถ้าไม่มี = กำลังรันผิดโปรเจกต์)
--
-- รันซ้ำได้ ไม่พัง
-- ─────────────────────────────────────────────────────────────


-- ═══ ตารางเก็บประวัติ ═════════════════════════════════════════

create table if not exists public.txn_edits (
  id         bigint generated always as identity primary key,
  txn_id     bigint      not null references public.txns(id) on delete cascade,
  edited_by  text        not null,          -- ชื่อบัญชีที่กดแก้
  edited_at  timestamptz not null default now(),
  changes    jsonb       not null           -- [{field, from, to}, ...]
);

create index if not exists txn_edits_txn_idx on public.txn_edits (txn_id, edited_at desc);


-- ═══ trigger — ฐานข้อมูลเป็นคนบันทึกเอง ไม่ใช่หน้าเว็บ ═════════

create or replace function public.log_txn_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare ch jsonb := '[]'::jsonb;
begin
  if new.ts     is distinct from old.ts     then ch := ch || jsonb_build_object('field','ts',    'from', old.ts::text,     'to', new.ts::text);     end if;
  if new.name   is distinct from old.name   then ch := ch || jsonb_build_object('field','name',  'from', old.name,         'to', new.name);         end if;
  if new.cat    is distinct from old.cat    then ch := ch || jsonb_build_object('field','cat',   'from', old.cat,          'to', new.cat);          end if;
  if new.method is distinct from old.method then ch := ch || jsonb_build_object('field','method','from', old.method,       'to', new.method);       end if;
  if new.kind   is distinct from old.kind   then ch := ch || jsonb_build_object('field','kind',  'from', old.kind,         'to', new.kind);         end if;
  if new.amt    is distinct from old.amt    then ch := ch || jsonb_build_object('field','amt',   'from', old.amt::text,    'to', new.amt::text);    end if;
  if new.code   is distinct from old.code   then ch := ch || jsonb_build_object('field','code',  'from', old.code,         'to', new.code);         end if;
  if new.flag   is distinct from old.flag   then ch := ch || jsonb_build_object('field','flag',  'from', old.flag,         'to', new.flag);         end if;
  if new.who    is distinct from old.who    then ch := ch || jsonb_build_object('field','who',   'from', old.who,          'to', new.who);          end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;

drop trigger if exists txns_log_edit on public.txns;
create trigger txns_log_edit
  after update on public.txns
  for each row execute function public.log_txn_edit();


-- ═══ สิทธิ์ — อ่านได้ถ้าล็อกอิน เขียนไม่ได้เลย ═════════════════

alter table public.txn_edits enable row level security;

drop policy if exists txn_edits_read on public.txn_edits;

create policy txn_edits_read on public.txn_edits
  for select to authenticated
  using (true);

revoke all on public.txn_edits from anon;


-- ═══ บอก PostgREST ให้โหลด schema ใหม่ ════════════════════════
-- ไม่งั้นหน้าเว็บจะยังขึ้น 404 PGRST205 ทั้งที่ตารางสร้างแล้ว

notify pgrst, 'reload schema';


-- ═══ ตรวจผล — ต้องได้ 1 แถว และทุกช่องต้องเป็น true / txn_edits ═══

select to_regclass('public.txn_edits')                                 as "ตารางถูกสร้าง",
       exists (select 1 from pg_trigger where tgname = 'txns_log_edit') as "trigger ติดแล้ว",
       (select count(*) from pg_policies
         where tablename = 'txn_edits')                                as "จำนวน policy",
       (select count(*) from public.profiles)                          as "บัญชีที่ผูกแล้ว";
