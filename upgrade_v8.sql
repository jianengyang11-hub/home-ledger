-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v8  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน upgrade_v6.sql (ตาราง budgets) มาก่อนแล้ว รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   เป้างบประมาณแยกตามคน — เพิ่มคอลัมน์ budgets.for_who
--   ว่าง (null) = เป้ากลางของบ้าน (พฤติกรรมเดิมทุกประการ)
--   มีชื่อ = เป้าส่วนตัวของบัญชีนั้น คิดยอดใช้จากรายการของคนนั้นเท่านั้น
--   ไม่ผูกกับตัวกรองบัญชีบนหน้าจอ (ดูหน้ารวมทุกบัญชีก็ยังเห็นเป้าส่วนตัวของแต่ละคนแยกกันถูก)
-- ─────────────────────────────────────────────────────────────

alter table public.budgets add column if not exists for_who text;

-- ผูกกับ profiles เหมือน to_who ใน txns — ใส่ชื่อที่ไม่มีอยู่จริงไม่ได้ (ข้าม null โดยอัตโนมัติ)
alter table public.budgets drop constraint if exists budgets_for_who_fkey;
alter table public.budgets
  add constraint budgets_for_who_fkey
  foreign key (for_who) references public.profiles(name)
  on update cascade
  on delete restrict;

notify pgrst, 'reload schema';

select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'budgets'
                  and column_name = 'for_who')                          as "คอลัมน์ for_who มีแล้ว",
       exists (select 1 from pg_constraint
                where conname = 'budgets_for_who_fkey'
                  and conrelid = to_regclass('public.budgets'))         as "ผูกกับ profiles แล้ว";
