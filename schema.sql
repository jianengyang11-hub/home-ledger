-- ─────────────────────────────────────────────────────────────
-- Home Ledger — โครงฐานข้อมูล
-- วิธีใช้: Supabase → SQL Editor → วางทั้งไฟล์นี้ → กด Run
-- ─────────────────────────────────────────────────────────────

create table if not exists public.txns (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  ts          date        not null,                -- วันที่ของรายการ
  name        text        not null default '',     -- ชื่อรายการ
  cat         text        not null default '',     -- หมวดหมู่
  method      text        not null default '',     -- ช่องทาง: เงินสด / โอน / บัตร
  who         text        not null,                -- ชื่อบัญชีที่บันทึก
  kind        text        not null check (kind in ('income','expense')),
  amt         numeric     not null check (amt >= 0),
  code        text        not null default 'THB',  -- สกุลเงิน: THB / USD / KIP
  flag        text        not null default ''      -- 'ประจำ' ถ้าเป็นรายการประจำ
);

create index if not exists txns_ts_idx on public.txns (ts desc, id desc);

alter table public.txns enable row level security;

-- เว็บนี้ไม่มีระบบล็อกอินจริง (ใช้ PIN ฝั่งหน้าเว็บ) ทุกคนที่เปิดเว็บ
-- จึงใช้ anon key ตัวเดียวกัน — DB แยกไม่ออกว่าใครเป็นใคร
-- กฎ "แก้/ลบได้เฉพาะบัญชีหลัก" จึงบังคับที่ฝั่งหน้าเว็บ
drop policy if exists txns_read   on public.txns;
drop policy if exists txns_insert on public.txns;
drop policy if exists txns_update on public.txns;
drop policy if exists txns_delete on public.txns;

create policy txns_read   on public.txns for select using (true);
create policy txns_insert on public.txns for insert with check (true);
create policy txns_update on public.txns for update using (true) with check (true);
create policy txns_delete on public.txns for delete using (true);
