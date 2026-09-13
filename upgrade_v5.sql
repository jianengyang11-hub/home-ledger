-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v5  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql, fix_txn_edits.sql, upgrade_v2.sql, upgrade_v3.sql มาก่อนแล้ว
-- (upgrade_v4.sql ไม่เกี่ยว ข้ามได้ถ้ายังไม่ได้รัน) รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   kind รับค่าใหม่ 1 แบบ  give (ส่งเงินให้คน) — ออกจาก method ของ who
--   ไปหาอีกคนตรง ๆ (to_who) ไม่ผ่านช่องทางไหนเลย ไม่ใช่รายรับ ไม่ใช่รายจ่าย
--   (เทียบเท่า "โอนระหว่างช่องทาง" แต่ปลายทางเป็นคน ไม่ใช่ช่องทาง)
--
-- ทำไมไม่ใช้ 2 แถว (รายจ่ายของคนส่ง + รายรับของคนรับ) แบบเดิม
--   เพราะนั่นคือ "ลายรับ ลายจ่าย" ที่ไม่ต้องการ — สองแถวสองเจ้าของ แก้/ยกเลิกไม่พร้อมกัน
--   และเผลอนับเป็นรายรับ-รายจ่ายจริงของบ้าน ทั้งที่เงินแค่เปลี่ยนมือ ไม่ได้เข้าออกบ้าน
-- ─────────────────────────────────────────────────────────────


-- ═══ 1. คอลัมน์ใหม่ ═══════════════════════════════════════════
-- ต่างจาก method_to ตรงที่ปล่อยให้เป็น null ได้ (ไม่ใช้ '' ว่าง)
-- เพื่อให้ผูก FK เข้ากับ profiles ได้ตรง ๆ — FK ข้าม null แถวที่ไม่ใช่ give จึงไม่ต้องมีข้อยกเว้น

alter table public.txns add column if not exists to_who text;


-- ═══ 2. ประเภทรายการใหม่ ══════════════════════════════════════
-- give  ส่งเงินให้คน   ออกจาก method ของ who → ไปหา to_who ตรง ๆ (ไม่ใช่รายรับ ไม่ใช่รายจ่าย)

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
  check (kind in ('income','expense','transfer','opening','give'));

-- ส่งเงินให้คนต้องมีคนรับ และต้องไม่ใช่ตัวเอง
alter table public.txns drop constraint if exists txns_give_check;
alter table public.txns add  constraint txns_give_check
  check (kind <> 'give' or (to_who is not null and to_who <> who));

-- ประเภทอื่นห้ามมีคนรับค้างไว้
alter table public.txns drop constraint if exists txns_to_who_check;
alter table public.txns add  constraint txns_to_who_check
  check (kind = 'give' or to_who is null);

-- ผูกคนรับเข้ากับ profiles เหมือน who — ใส่ชื่อที่ไม่มีอยู่จริงไม่ได้ (ข้าม null โดยอัตโนมัติ)
alter table public.txns drop constraint if exists txns_to_who_fkey;
alter table public.txns
  add constraint txns_to_who_fkey
  foreign key (to_who) references public.profiles(name)
  on update cascade
  on delete restrict;


-- ═══ 3. ประวัติการแก้ไข — บันทึกช่องใหม่ด้วย ═══════════════════

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
  if new.void_at   is distinct from old.void_at   then ch := ch || jsonb_build_object('field','void',
    'from', case when old.void_at is null then '' else 'ยกเลิก · ' || old.void_reason end,
    'to',   case when new.void_at is null then '' else 'ยกเลิก · ' || btrim(new.void_reason) end); end if;

  if jsonb_array_length(ch) > 0 then
    insert into public.txn_edits (txn_id, edited_by, changes)
    values (old.id, coalesce(public.my_name(), '?'), ch);
  end if;
  return new;
end $$;


-- ═══ บอก PostgREST ให้โหลด schema ใหม่ ════════════════════════

notify pgrst, 'reload schema';


-- ═══ ตรวจผล — ต้องได้ 1 แถว ทุกช่องเป็น true ═══════════════════

select exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'txns'
                  and column_name = 'to_who')                          as "คอลัมน์ to_who มีแล้ว",
       exists (select 1 from pg_constraint
                where conname = 'txns_to_who_fkey'
                  and conrelid = to_regclass('public.txns'))           as "ผูกคนรับกับ profiles แล้ว",
       (select pg_get_constraintdef(oid) from pg_constraint
         where conname = 'txns_kind_check'
           and conrelid = to_regclass('public.txns'))                  as "kind ที่ยอมรับตอนนี้";
