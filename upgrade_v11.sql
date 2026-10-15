-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v11 · แลกเปลี่ยนเงินตราภายใน
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- รันหลัง upgrade_v10.sql แล้ว รันซ้ำได้
--
-- อัตราแลกเปลี่ยนบันทึกตามที่ผู้ใช้กรอกในวันที่ทำรายการ
-- รายการแลกเปลี่ยนเป็นแถวเดียว ไม่ถูกนับเป็นรายรับหรือรายจ่าย
-- ─────────────────────────────────────────────────────────────

alter table public.txns add column if not exists exchange_to_amt numeric;
alter table public.txns add column if not exists exchange_to_code text;
alter table public.txns add column if not exists exchange_rate numeric;
alter table public.txns add column if not exists exchange_side text;
alter table public.txns add column if not exists service_fee numeric not null default 0;

update public.txns
   set exchange_side = 'sell'
 where kind = 'exchange' and exchange_side is null;

alter table public.txns drop constraint if exists txns_kind_check;

alter table public.txns add constraint txns_kind_check
  check (kind in ('income','expense','transfer','opening','give','exchange'));

alter table public.txns drop constraint if exists txns_exchange_check;
alter table public.txns add constraint txns_exchange_check
  check (
    (kind = 'exchange'
      and exchange_to_amt is not null
      and exchange_to_amt > 0
      and exchange_to_code is not null
      and exchange_to_code <> code
      and exchange_rate is not null
      and exchange_rate > 0
      and exchange_side in ('buy','sell'))
    or
    (kind <> 'exchange'
      and exchange_to_amt is null
      and exchange_to_code is null
      and exchange_rate is null
      and exchange_side is null)
  );

alter table public.txns drop constraint if exists txns_service_fee_check;
alter table public.txns add constraint txns_service_fee_check
  check (
    service_fee >= 0
    and (
      service_fee = 0
      or kind = 'exchange'
      or (
        kind in ('income','expense')
        and method in ('โอน','บัตร')
        and (kind <> 'income' or service_fee <= amt)
      )
    )
  );

create or replace function public.log_txn_exchange_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare ch jsonb := '[]'::jsonb;
begin
  if new.service_fee is distinct from old.service_fee then
    ch := ch || jsonb_build_object('field','service_fee','from',old.service_fee::text,'to',new.service_fee::text);
  end if;
  if new.exchange_to_amt is distinct from old.exchange_to_amt then
    ch := ch || jsonb_build_object('field','exchange_to_amt','from',old.exchange_to_amt::text,'to',new.exchange_to_amt::text);
  end if;
  if new.exchange_to_code is distinct from old.exchange_to_code then
    ch := ch || jsonb_build_object('field','exchange_to_code','from',old.exchange_to_code,'to',new.exchange_to_code);
  end if;
  if new.exchange_rate is distinct from old.exchange_rate then
    ch := ch || jsonb_build_object('field','exchange_rate','from',old.exchange_rate::text,'to',new.exchange_rate::text);
  end if;
  if new.exchange_side is distinct from old.exchange_side then
    ch := ch || jsonb_build_object('field','exchange_side','from',old.exchange_side,'to',new.exchange_side);
  end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;

drop trigger if exists txn_exchange_edit_log on public.txns;
create trigger txn_exchange_edit_log
  after update on public.txns
  for each row execute function public.log_txn_exchange_edit();

notify pgrst, 'reload schema';

select
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'txns'
             and column_name = 'exchange_to_amt') as "คอลัมน์แลกเปลี่ยนมีแล้ว",
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'txns'
             and column_name = 'service_fee') as "คอลัมน์ค่าบริการมีแล้ว",
  exists (select 1 from information_schema.columns
           where table_schema = 'public' and table_name = 'txns'
             and column_name = 'exchange_side') as "คอลัมน์ทิศทางแลกเปลี่ยนมีแล้ว",
  exists (select 1 from pg_constraint
           where conname = 'txns_exchange_check'
             and conrelid = to_regclass('public.txns')) as "ตรวจข้อมูลแลกเปลี่ยนแล้ว",
  exists (select 1 from pg_constraint
           where conname = 'txns_service_fee_check'
             and conrelid = to_regclass('public.txns')) as "ตรวจค่าบริการแล้ว",
  exists (select 1 from pg_constraint
           where conname = 'txns_kind_check'
             and conrelid = to_regclass('public.txns')
             and pg_get_constraintdef(oid) ilike '%exchange%') as "ประเภทรายการแลกเปลี่ยนใช้ได้";
