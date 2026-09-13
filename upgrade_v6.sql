-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v6  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql, fix_txn_edits.sql, upgrade_v2.sql มาก่อนแล้ว รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   ตาราง budgets — เป้างบประมาณต่อเดือน (รวมถึง "เป้าหมายออม") ย้ายจาก config.js
--   มาเก็บในฐานข้อมูลจริง ทุกคนเห็นชุดเดียวกัน แก้ได้เฉพาะบัญชีหลัก ผ่านหน้า "ตั้งค่า"
--   (หลักการเดียวกับตาราง cats ใน upgrade_v2.sql ข้อ 6 — เพิ่ม/ลบได้กี่แถวก็ได้จากหน้าเว็บ
--   ไม่ต้องมีคนเข้าไปแก้ config.js อีกต่อไป เพราะคนอื่นไม่มีสิทธิ์เข้าถึง backend)
-- ─────────────────────────────────────────────────────────────


-- ═══ 1. ตารางเป้างบประมาณ ══════════════════════════════════════

create table if not exists public.budgets (
  id    bigint generated always as identity primary key,
  cat   text    not null,               -- ชื่อหมวด หรือ "เป้าหมายออม" (ค่าพิเศษ)
  amt   numeric not null default 0 check (amt >= 0),
  code  text    not null default 'KIP', -- สกุลเงิน — ไม่แปลงค่าข้ามสกุล เหมือนที่อื่นในระบบ
  sort  int     not null default 0
);

alter table public.budgets enable row level security;

drop policy if exists budgets_read   on public.budgets;
drop policy if exists budgets_write  on public.budgets;
drop policy if exists budgets_update on public.budgets;
drop policy if exists budgets_delete on public.budgets;

-- ทุกคนที่ล็อกอินอ่านได้ · แก้ได้เฉพาะบัญชีหลัก (เหมือนตาราง cats ทุกประการ)
create policy budgets_read   on public.budgets for select to authenticated using (true);
create policy budgets_write  on public.budgets for insert to authenticated with check (public.is_admin());
create policy budgets_update on public.budgets for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy budgets_delete on public.budgets for delete to authenticated using (public.is_admin());

revoke all on public.budgets from anon;


-- ═══ 2. ยกของเดิมจาก config.js มาตั้งต้น — ครั้งเดียว ถ้าตารางยังว่าง ═══
-- รันซ้ำไม่เพิ่มซ้ำ · ถ้าอยากได้ชุดอื่นแทน ไปแก้/ลบ/เพิ่มที่หน้า "ตั้งค่า" ได้เลยหลังรันไฟล์นี้

insert into public.budgets (cat, amt, code, sort)
select v.cat, v.amt, v.code, v.sort from (values
  ('อาหาร',        3000000::numeric, 'KIP', 1),
  ('เดินทาง',      1200000::numeric, 'KIP', 2),
  ('บันเทิง',      800000::numeric,  'KIP', 3),
  ('เป้าหมายออม',  6000000::numeric, 'KIP', 4)
) as v(cat, amt, code, sort)
where not exists (select 1 from public.budgets);


-- ═══ บอก PostgREST ให้โหลด schema ใหม่ ════════════════════════

notify pgrst, 'reload schema';


-- ═══ ตรวจผล ═══════════════════════════════════════════════════

select (select count(*) from public.budgets)                            as "จำนวนเป้างบประมาณ",
       (select count(*) from pg_policies where tablename = 'budgets')   as "policy ของ budgets (ควรเป็น 4)";
