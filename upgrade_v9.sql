-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v9  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน upgrade_v8.sql (คอลัมน์ budgets.for_who) มาก่อนแล้ว รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   เป้างบประมาณส่วนตัว (budgets.for_who = ชื่อตัวเอง) ให้สมาชิกทั่วไปเพิ่ม/แก้/ลบเองได้
--   เหมือนหลักการเดียวกับ txns.who — "who = my_name() or is_admin()"
--   ส่วนเป้ากลางของบ้าน (for_who ว่าง) และเป้าส่วนตัวของคนอื่น ยังแก้ได้เฉพาะบัญชีหลักเหมือนเดิม
-- ─────────────────────────────────────────────────────────────

drop policy if exists budgets_write  on public.budgets;
drop policy if exists budgets_update on public.budgets;
drop policy if exists budgets_delete on public.budgets;

create policy budgets_write  on public.budgets
  for insert to authenticated
  with check ( public.is_admin() or for_who = public.my_name() );

create policy budgets_update on public.budgets
  for update to authenticated
  using      ( public.is_admin() or for_who = public.my_name() )
  with check ( public.is_admin() or for_who = public.my_name() );

create policy budgets_delete on public.budgets
  for delete to authenticated
  using ( public.is_admin() or for_who = public.my_name() );

notify pgrst, 'reload schema';

select policyname, cmd, with_check from pg_policies
 where tablename = 'budgets' and policyname in ('budgets_write','budgets_update','budgets_delete')
 order by policyname;
