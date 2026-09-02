-- ─────────────────────────────────────────────────────────────
-- Home Ledger — โครงฐานข้อมูล + ความปลอดภัยจริง (Supabase Auth + RLS)
--
-- วิธีใช้: Supabase → SQL Editor → วางทั้งไฟล์นี้ → กด Run
-- รันซ้ำได้ ไม่พัง (idempotent)
--
-- หลังรันเสร็จต้องไปสร้างผู้ใช้ 3 คนใน Authentication → Users
-- แล้วกลับมารันบล็อกสุดท้าย (ผูกผู้ใช้กับชื่อบัญชี)
-- ─────────────────────────────────────────────────────────────


-- ═══ 1. ตารางรายการ ═══════════════════════════════════════════

create table if not exists public.txns (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  ts          date        not null,
  name        text        not null default '',
  cat         text        not null default '',
  method      text        not null default '',
  who         text        not null,
  kind        text        not null check (kind in ('income','expense')),
  amt         numeric     not null check (amt >= 0),
  code        text        not null default 'THB',
  flag        text        not null default ''
);

create index if not exists txns_ts_idx on public.txns (ts desc, id desc);


-- ═══ 2. โปรไฟล์ — ผูก auth user เข้ากับชื่อบัญชีในสมุด ═══════════

create table if not exists public.profiles (
  id    uuid primary key references auth.users(id) on delete cascade,
  name  text not null unique,                                  -- ปิ่น / ต้น / บ้านเรา
  role  text not null default 'member' check (role in ('admin','member')),
  code  text not null default 'KIP'                            -- สกุลเงินหลักของบัญชี
);


-- ═══ 3. ฟังก์ชันช่วย ═══════════════════════════════════════════
-- security definer เพื่ออ่าน profiles ได้โดยไม่วน RLS ซ้อนตัวเอง

create or replace function public.my_name()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select name from public.profiles where id = auth.uid()
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select role = 'admin' from public.profiles where id = auth.uid()), false)
$$;


-- ═══ 4. RLS — กฎสิทธิ์จริง บังคับที่ฐานข้อมูล ══════════════════

alter table public.txns     enable row level security;
alter table public.profiles enable row level security;

-- ล้างนโยบายเดิมทั้งหมด (รวมของเวอร์ชันเก่าที่เปิดให้ anon)
drop policy if exists txns_read   on public.txns;
drop policy if exists txns_insert on public.txns;
drop policy if exists txns_update on public.txns;
drop policy if exists txns_delete on public.txns;
drop policy if exists txns_select on public.txns;
drop policy if exists profiles_read on public.profiles;

-- อ่าน: ต้องล็อกอินแล้วเท่านั้น (คนไม่ล็อกอิน = anon อ่านไม่ได้เลย)
create policy txns_select on public.txns
  for select to authenticated
  using (true);

-- เพิ่ม: บันทึกได้เฉพาะในชื่อบัญชีตัวเอง — บัญชีหลักบันทึกแทนคนอื่นได้
create policy txns_insert on public.txns
  for insert to authenticated
  with check ( who = public.my_name() or public.is_admin() );

-- แก้: บัญชีหลักเท่านั้น
create policy txns_update on public.txns
  for update to authenticated
  using      ( public.is_admin() )
  with check ( public.is_admin() );

-- ลบ: บัญชีหลักเท่านั้น
create policy txns_delete on public.txns
  for delete to authenticated
  using ( public.is_admin() );

-- โปรไฟล์: ล็อกอินแล้วอ่านได้ แต่ไม่มีใครแก้ผ่าน API ได้
-- (ไม่มี policy สำหรับ insert/update/delete = ทำไม่ได้ แก้ได้ใน dashboard เท่านั้น)
create policy profiles_read on public.profiles
  for select to authenticated
  using (true);

-- ตัดสิทธิ์ anon ออกให้ขาด
revoke all on public.txns     from anon;
revoke all on public.profiles from anon;


-- ═══ 5. ผูกผู้ใช้กับชื่อบัญชี ═══════════════════════════════════
--
-- ทำหลังจากสร้างผู้ใช้ใน Authentication → Users แล้ว
-- แก้อีเมลให้ตรงกับที่สร้างไว้จริง แล้วรันเฉพาะบล็อกนี้ซ้ำได้
--
-- ปิ่น = admin (แก้/ลบได้)   ต้น กับ บ้านเรา = member (เพิ่มได้อย่างเดียว)

insert into public.profiles (id, name, role, code)
select u.id, v.name, v.role, v.code
from auth.users u
join (values
  ('jianengyang11@gmail.com', 'ปิ่น',     'admin',  'KIP'),
  ('jia@gmail.com',           'ต้น',      'member', 'KIP'),
  ('yang11@gmail.com',        'บ้านเรา',  'member', 'KIP')
) as v(email, name, role, code) on lower(u.email) = v.email
on conflict (id) do update
  set name = excluded.name,
      role = excluded.role,
      code = excluded.code;


-- ═══ ตรวจผล ═══════════════════════════════════════════════════
-- ควรเห็น 3 แถว และ ปิ่น ต้องเป็น admin
select p.name, p.role, p.code, u.email
from public.profiles p join auth.users u on u.id = p.id
order by p.role, p.name;
