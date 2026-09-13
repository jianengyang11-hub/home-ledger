-- ─────────────────────────────────────────────────────────────
-- Home Ledger v2 — ยอดคงเหลือแยกช่องทาง + ยกเลิกรายการแทนการลบทิ้ง
--
-- วิธีใช้: Supabase → SQL Editor → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql กับ fix_txn_edits.sql มาก่อนแล้ว
-- รันซ้ำได้ ไม่พัง
--
-- สิ่งที่เปลี่ยน
--   1. kind รับค่าใหม่ 2 แบบ  transfer (โอนระหว่างช่องทาง) · opening (ยอดยกมา)
--   2. method_to  ปลายทางของการโอน เช่น ถอน ATM = โอน → เงินสด
--   3. void_at / void_by / void_reason  ยกเลิกรายการโดยไม่ลบทิ้ง ต้องมีเหตุผล กู้คืนได้
--   4. ปิดการลบถาวรผ่าน API ทุกกรณี ประวัติการแก้ไขจึงหายไม่ได้อีก
--   5. ตาราง cats — หมวดหมู่เก็บในฐานข้อมูลจริง ไม่ใช่ค้างในหน้าเว็บแล้วหายตอนรีเฟรช
-- ─────────────────────────────────────────────────────────────


-- ═══ 1. คอลัมน์ใหม่ ═══════════════════════════════════════════

alter table public.txns add column if not exists method_to   text not null default '';
alter table public.txns add column if not exists void_at     timestamptz;
alter table public.txns add column if not exists void_by     text;
alter table public.txns add column if not exists void_reason text not null default '';

create index if not exists txns_live_idx on public.txns (ts desc, id desc) where void_at is null;


-- ═══ 2. ประเภทรายการใหม่ ══════════════════════════════════════
-- income   รายรับ        เข้าช่องทาง method
-- expense  รายจ่าย       ออกจากช่องทาง method
-- transfer โอนระหว่างช่องทาง  ออกจาก method → เข้า method_to (ไม่ใช่รายรับ ไม่ใช่รายจ่าย)
-- opening  ยอดยกมา       เงินตั้งต้นของช่องทาง ไม่นับเป็นรายรับของงวดไหน

-- ไล่ลบกฎเดิมของ kind ทุกตัว โดยดูจากเนื้อกฎ ไม่ใช่ชื่อ
-- (กฎที่เขียนติดมากับ create table อาจถูกตั้งชื่ออัตโนมัติเป็นอย่างอื่น
--  ถ้าลบไม่ตรงชื่อ กฎเก่าที่ยอมแค่ income/expense จะค้างอยู่ แล้วบันทึกรายการโอนไม่ได้)
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.txns'::regclass
              and contype = 'c'
              and pg_get_constraintdef(oid) ilike '%kind%'
  loop
    execute format('alter table public.txns drop constraint %I', c.conname);
  end loop;
end $$;

alter table public.txns add constraint txns_kind_check
  check (kind in ('income','expense','transfer','opening'));

-- โอนต้องมีปลายทาง และปลายทางต้องไม่ใช่ช่องทางเดิม
alter table public.txns drop constraint if exists txns_transfer_check;
alter table public.txns add  constraint txns_transfer_check
  check (kind <> 'transfer' or (method_to <> '' and method_to <> method));

-- ประเภทอื่นห้ามมีปลายทางค้างไว้
alter table public.txns drop constraint if exists txns_method_to_check;
alter table public.txns add  constraint txns_method_to_check
  check (kind = 'transfer' or method_to = '');


-- ═══ 3. ยกเลิกรายการ — ฐานข้อมูลเป็นคนเขียนว่าใครยกเลิกเมื่อไหร่ ═══
-- หน้าเว็บส่งมาแค่ void_at ค่าอะไรก็ได้ trigger จะเขียนทับด้วย now() กับชื่อจริง
-- ส่ง void_at = null คือกู้คืน

create or replace function public.guard_txn_void()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    new.void_at     := null;                   -- เพิ่มรายการมาแบบยกเลิกแล้วไม่ได้
    new.void_by     := null;
    new.void_reason := '';
    return new;
  end if;

  if new.void_at is distinct from old.void_at then
    if not public.is_admin() then
      raise exception 'เฉพาะบัญชีหลักเท่านั้นที่ยกเลิกหรือกู้คืนรายการได้';
    end if;
    if new.void_at is null then
      new.void_by     := null;                 -- กู้คืน
      new.void_reason := '';
    else
      if coalesce(btrim(new.void_reason), '') = '' then
        raise exception 'ต้องระบุเหตุผลที่ยกเลิกรายการ';
      end if;
      new.void_at     := now();                -- ยกเลิก
      new.void_by     := coalesce(public.my_name(), '?');
      new.void_reason := btrim(new.void_reason);
    end if;
  else
    -- ไม่ได้ยกเลิกหรือกู้คืน ก็แก้ร่องรอยการยกเลิกไม่ได้เลย
    new.void_by     := old.void_by;
    new.void_reason := old.void_reason;
  end if;
  return new;
end $$;

drop trigger if exists txns_guard_void on public.txns;
create trigger txns_guard_void
  before insert or update on public.txns
  for each row execute function public.guard_txn_void();


-- ═══ 4. ปิดการลบถาวร ══════════════════════════════════════════
-- ไม่มี policy สำหรับ delete = ลบผ่าน API ไม่ได้เลย แม้แต่บัญชีหลัก
-- ประวัติการแก้ไข (on delete cascade) จึงหายตามไปไม่ได้อีก
-- ถ้าต้องลบจริง ๆ ทำได้ที่ Supabase dashboard เท่านั้น

drop policy if exists txns_delete on public.txns;
drop policy if exists txns_read   on public.txns;   -- เก็บกวาด policy หลวมของเวอร์ชันเก่า


-- ═══ 5. ประวัติการแก้ไข — บันทึกช่องใหม่ด้วย ═══════════════════

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
  if new.kind      is distinct from old.kind      then ch := ch || jsonb_build_object('field','kind',     'from', old.kind,          'to', new.kind);          end if;
  if new.amt       is distinct from old.amt       then ch := ch || jsonb_build_object('field','amt',      'from', old.amt::text,     'to', new.amt::text);     end if;
  if new.code      is distinct from old.code      then ch := ch || jsonb_build_object('field','code',     'from', old.code,          'to', new.code);          end if;
  if new.flag      is distinct from old.flag      then ch := ch || jsonb_build_object('field','flag',     'from', old.flag,          'to', new.flag);          end if;
  if new.who       is distinct from old.who       then ch := ch || jsonb_build_object('field','who',      'from', old.who,           'to', new.who);           end if;
  if new.void_at   is distinct from old.void_at   then ch := ch || jsonb_build_object('field','void',
    'from', case when old.void_at is null then '' else 'ยกเลิก · ' || old.void_reason end,
    'to',   case when new.void_at is null then '' else 'ยกเลิก · ' || btrim(new.void_reason) end); end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;


-- ═══ 6. หมวดหมู่ — เก็บในฐานข้อมูลจริง ═════════════════════════
-- ของเดิมหมวดหมู่อยู่ในหน้าเว็บล้วน ๆ กดเพิ่ม/แก้/ลบได้ แต่รีเฟรชแล้วหาย
-- และอีกคนไม่มีวันเห็น — ปุ่มทำงานหลอก ๆ

create table if not exists public.cats (
  id    bigint generated always as identity primary key,
  th    text    not null,
  lo    text    not null default '',
  sort  int     not null default 0
);

alter table public.cats enable row level security;

drop policy if exists cats_read   on public.cats;
drop policy if exists cats_write  on public.cats;
drop policy if exists cats_update on public.cats;
drop policy if exists cats_delete on public.cats;

-- ทุกคนที่ล็อกอินอ่านได้ · แก้ได้เฉพาะบัญชีหลัก
create policy cats_read   on public.cats for select to authenticated using (true);
create policy cats_write  on public.cats for insert to authenticated with check (public.is_admin());
create policy cats_update on public.cats for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy cats_delete on public.cats for delete to authenticated using (public.is_admin());

revoke all on public.cats from anon;

-- ใส่ชุดเริ่มต้นให้ครั้งเดียว ถ้าตารางยังว่าง (รันซ้ำไม่เพิ่มซ้ำ)
insert into public.cats (th, lo, sort)
select v.th, v.lo, v.sort from (values
  ('อาหาร',          'ອາຫານ',              1),
  ('ที่อยู่อาศัย',    'ທີ່ຢູ່ອາໄສ',          2),
  ('เดินทาง',        'ການເດີນທາງ',          3),
  ('ลูก',            'ລູກ',                4),
  ('ของใช้ในบ้าน',   'ເຄື່ອງໃຊ້ໃນເຮືອນ',    5),
  ('สุขภาพ',         'ສຸຂະພາບ',            6),
  ('บันเทิง',        'ບັນເທິງ',            7),
  ('อื่น ๆ',         'ອື່ນໆ',              8)
) as v(th, lo, sort)
where not exists (select 1 from public.cats);


-- ═══ 7. รายการประจำ — ทำให้มันทำงานจริง ═══════════════════════
-- ของเดิมธง "ประจำ" เป็นแค่ป้ายข้อความ ไม่มีอะไรสร้างรายการซ้ำให้เลย
-- ทั้งที่หน้าเว็บเขียนว่า "จะสร้างรายการอัตโนมัติ"
--
-- ไม่ใช้ pg_cron เพื่อไม่ต้องพึ่ง extension ที่อาจเปิดไม่ได้
-- หน้าเว็บเรียกฟังก์ชันนี้ให้เองหลังล็อกอิน — เปิดแอปเมื่อไหร่ก็ตามให้ครบเมื่อนั้น
-- (ถ้าอยากให้เดินเองด้วย ค่อยเอาไปตั้ง cron.schedule ทีหลังได้ ฟังก์ชันเดียวกัน)

create or replace function public.run_recurring()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  made  int := 0;
  src   record;
  m     date;
  d     int;
  newts date;
begin
  if public.my_name() is null then
    raise exception 'ต้องเข้าสู่ระบบก่อน';
  end if;

  -- แม่แบบ = รายการล่าสุดของแต่ละชุดที่ติดธง "ประจำ" และยังไม่ถูกยกเลิก
  for src in
    select distinct on (who, name, cat, method, kind, amt, code)
           ts, name, cat, method, method_to, who, kind, amt, code
      from public.txns
     where flag = 'ประจำ' and void_at is null and kind in ('income','expense')
     order by who, name, cat, method, kind, amt, code, ts desc
  loop
    d := extract(day from src.ts)::int;
    m := (date_trunc('month', src.ts) + interval '1 month')::date;

    -- ไล่เติมทีละเดือนจนถึงเดือนปัจจุบัน เผื่อไม่ได้เปิดแอปหลายเดือน
    while m <= date_trunc('month', current_date)::date loop
      -- เดือนที่สั้นกว่า เช่น ตั้งไว้วันที่ 31 แต่เดือนนั้นมี 30 วัน → ใช้วันสุดท้ายแทน
      newts := (m + (least(d, extract(day from (m + interval '1 month' - interval '1 day'))::int) - 1) * interval '1 day')::date;

      if not exists (
        select 1 from public.txns x
         where x.who = src.who and x.name = src.name and x.cat = src.cat
           and x.method = src.method and x.kind = src.kind
           and x.amt = src.amt and x.code = src.code
           and x.ts >= m and x.ts < (m + interval '1 month')
      ) then
        insert into public.txns (ts, name, cat, method, method_to, who, kind, amt, code, flag)
        values (newts, src.name, src.cat, src.method, src.method_to, src.who, src.kind, src.amt, src.code, 'ประจำ');
        made := made + 1;
      end if;

      m := (m + interval '1 month')::date;
    end loop;
  end loop;

  return made;
end $$;

revoke all on function public.run_recurring() from public, anon;
grant execute on function public.run_recurring() to authenticated;


-- ═══ บอก PostgREST ให้โหลด schema ใหม่ ════════════════════════

notify pgrst, 'reload schema';


-- ═══ ตรวจผล — ต้องได้ 1 แถว ทุกช่องเป็น true ═══════════════════

select (select count(*) = 4 from information_schema.columns  -- ต้องได้ true ทุกช่อง
          where table_schema = 'public' and table_name = 'txns'
            and column_name in ('method_to','void_at','void_by','void_reason')) as "คอลัมน์ใหม่ครบ",
       exists (select 1 from pg_trigger where tgname = 'txns_guard_void')  as "trigger ยกเลิกติดแล้ว",
       not exists (select 1 from pg_policies
          where tablename = 'txns' and cmd = 'DELETE')                     as "ลบถาวรถูกปิดแล้ว",
       (select count(*) from pg_policies where tablename = 'txns')         as "policy ของ txns (ควรเป็น 3)",
       (select count(*) from public.cats)                                  as "หมวดหมู่ในฐานข้อมูล";
