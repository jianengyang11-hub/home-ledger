-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v10 · ช่องทางรับเงินของผู้รับ
--
-- วิธีใช้: Supabase → SQL Editor → New query → วางทั้งไฟล์ → Run
-- ต้องรัน upgrade_v5.sql มาก่อนแล้ว รันซ้ำได้
--
-- รายการ give เดิมยังคง to_method เป็น null เพราะฐานข้อมูลไม่มีข้อมูลว่า
-- ผู้รับเก็บเงินไว้ช่องทางใด — แก้รายการเดิมจากหน้าเว็บเพื่อระบุช่องทางรับ
-- ─────────────────────────────────────────────────────────────

alter table public.txns add column if not exists to_method text;

alter table public.txns drop constraint if exists txns_to_method_check;
alter table public.txns add constraint txns_to_method_check
  check (to_method is null or to_method in ('เงินสด','โอน','บัตร'));

alter table public.txns drop constraint if exists txns_to_method_kind_check;
alter table public.txns add constraint txns_to_method_kind_check
  check (kind = 'give' or to_method is null);

create index if not exists txns_to_who_live_idx
  on public.txns (to_who, ts desc, id desc)
  where kind = 'give' and void_at is null;

-- เก็บประวัติช่องทางรับเงินด้วย และคงการติดตามฟิลด์ที่เพิ่มใน v4, v5, v2
create or replace function public.log_txn_edit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare ch jsonb := '[]'::jsonb;
begin
  if new.ts        is distinct from old.ts        then ch := ch || jsonb_build_object('field','ts',        'from', old.ts::text,      'to', new.ts::text);      end if;
  if new.name      is distinct from old.name      then ch := ch || jsonb_build_object('field','name',      'from', old.name,          'to', new.name);          end if;
  if new.cat       is distinct from old.cat       then ch := ch || jsonb_build_object('field','cat',       'from', old.cat,           'to', new.cat);           end if;
  if new.method    is distinct from old.method    then ch := ch || jsonb_build_object('field','method',    'from', old.method,        'to', new.method);        end if;
  if new.method_to is distinct from old.method_to then ch := ch || jsonb_build_object('field','method_to', 'from', old.method_to,     'to', new.method_to);     end if;
  if new.to_who    is distinct from old.to_who    then ch := ch || jsonb_build_object('field','to_who',    'from', old.to_who,        'to', new.to_who);        end if;
  if new.to_method is distinct from old.to_method then ch := ch || jsonb_build_object('field','to_method', 'from', old.to_method,     'to', new.to_method);     end if;
  if new.kind      is distinct from old.kind      then ch := ch || jsonb_build_object('field','kind',      'from', old.kind,          'to', new.kind);          end if;
  if new.amt       is distinct from old.amt       then ch := ch || jsonb_build_object('field','amt',       'from', old.amt::text,     'to', new.amt::text);     end if;
  if new.code      is distinct from old.code      then ch := ch || jsonb_build_object('field','code',      'from', old.code,          'to', new.code);          end if;
  if new.flag      is distinct from old.flag      then ch := ch || jsonb_build_object('field','flag',      'from', old.flag,          'to', new.flag);          end if;
  if new.who       is distinct from old.who       then ch := ch || jsonb_build_object('field','who',       'from', old.who,           'to', new.who);           end if;
  if (to_jsonb(new)->'slip') is distinct from (to_jsonb(old)->'slip') then
    ch := ch || jsonb_build_object('field','slip', 'from', to_jsonb(old)->>'slip', 'to', to_jsonb(new)->>'slip');
  end if;
  if new.void_at   is distinct from old.void_at   then ch := ch || jsonb_build_object('field','void',
    'from', case when old.void_at is null then '' else 'ยกเลิก · ' || old.void_reason end,
    'to',   case when new.void_at is null then '' else 'ยกเลิก · ' || btrim(new.void_reason) end); end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;

notify pgrst, 'reload schema';

select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'txns'
                  and column_name = 'to_method') as "คอลัมน์ to_method มีแล้ว",
       exists (select 1 from pg_constraint
                where conname = 'txns_to_method_kind_check'
                  and conrelid = to_regclass('public.txns')) as "ตรวจชนิดรายการแล้ว",
       (select count(*) from public.txns
         where kind = 'give' and to_method is null) as "รายการส่งเงินเดิมที่ยังไม่ระบุช่องทางรับ";
