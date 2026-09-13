-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v4  ·  แนบสลิปได้จริง  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql, fix_txn_edits.sql, upgrade_v2.sql, upgrade_v3.sql มาก่อนแล้ว
-- รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   1. คอลัมน์ txns.slip — เก็บ "ที่อยู่ไฟล์" ใน Storage ไม่ใช่ตัวไฟล์
--   2. ถัง (bucket) ชื่อ slips — ปิดสาธารณะ จำกัด 5 MB รับแค่ JPG / PNG / PDF
--   3. สิทธิ์ของถัง — ล็อกอินแล้วอ่านและอัปได้ · ทับของเดิมกับลบทิ้งไม่ได้เลย
--   4. trigger ประวัติการแก้ไข บันทึกการเปลี่ยนสลิปด้วย
--
-- แต่ละข้อห่อด้วย exception ของตัวเอง ข้อไหนติดปัญหาก็ล้มเฉพาะข้อนั้น
-- **ดูตารางผลลัพธ์ท้ายไฟล์พอ** ขึ้น ✓ ครบ 4 แถว = จบ ปิดได้เลย
--
-- ทำไมถังไม่เปิดสาธารณะ: สลิปมีเลขบัญชี ยอดเงิน ชื่อคน
-- ถ้าเปิดสาธารณะใครเดา URL ถูกก็เปิดดูได้โดยไม่ต้องล็อกอิน
-- หน้าเว็บจึงขอ "ลิงก์ชั่วคราว" (signed URL) อายุ 1 ชั่วโมงทุกครั้งที่กดเปิดดู
--
-- ทำไมไม่ให้ลบ/ทับไฟล์: หลักการเดียวกับ txn_edits — ลบสลิปได้ก็ลบหลักฐานได้
-- เปลี่ยนสลิปคือ "อัปไฟล์ใหม่แล้วชี้ไปไฟล์ใหม่" ไฟล์เก่ายังอยู่ในถัง
-- ข้อแลกเปลี่ยน: ไฟล์ที่ไม่มีใครชี้ถึงจะค้างสะสมในถัง ต้องไปลบเองใน dashboard ถ้าอยากเก็บกวาด
-- ─────────────────────────────────────────────────────────────


-- ═══ 0. ที่เก็บผลระหว่างทาง ════════════════════════════════════

drop table if exists _v4_log;
create temp table _v4_log (step int primary key, detail text);


-- ═══ 1. คอลัมน์ slip ═══════════════════════════════════════════
-- เก็บแค่ path เช่น '2026-09/3f2a....jpg' — ตัวไฟล์อยู่ใน Storage
-- ค่าว่าง '' = ไม่ได้แนบ (ใช้ '' ไม่ใช่ null ให้เหมือนคอลัมน์ข้อความอื่นในตารางนี้)

do $$
begin
  alter table public.txns add column if not exists slip text not null default '';
exception when others then
  insert into _v4_log values (1, 'เพิ่มคอลัมน์ไม่สำเร็จ: ' || sqlerrm);
end $$;


-- ═══ 2. ถังเก็บไฟล์ ════════════════════════════════════════════
-- public = false → ต้องมี token ถึงจะอ่านได้ ไม่มีลิงก์ถาวรให้ใครเดา

do $$
begin
  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('slips', 'slips', false, 5242880,
          array['image/jpeg', 'image/png', 'application/pdf'])
  on conflict (id) do update
    set public            = false,
        file_size_limit   = 5242880,
        allowed_mime_types = array['image/jpeg', 'image/png', 'application/pdf'];
exception when others then
  insert into _v4_log values (2, 'สร้างถังไม่สำเร็จ: ' || sqlerrm ||
    '   ·   ถ้าติดสิทธิ์ ให้ไปสร้างเองที่ Storage → New bucket ชื่อ slips แบบ Private จำกัด 5 MB');
end $$;


-- ═══ 3. สิทธิ์ของถัง ═══════════════════════════════════════════
-- อ่าน/อัปได้เมื่อล็อกอินแล้วเท่านั้น · ไม่มี policy update/delete
-- = ทับไฟล์เดิมไม่ได้ ลบไม่ได้ แม้บัญชีหลักและแม้เรียก API ตรง

do $$
begin
  drop policy if exists slips_read   on storage.objects;
  drop policy if exists slips_insert on storage.objects;

  create policy slips_read on storage.objects
    for select to authenticated using (bucket_id = 'slips');

  create policy slips_insert on storage.objects
    for insert to authenticated with check (bucket_id = 'slips');
exception when others then
  insert into _v4_log values (3, 'ตั้งสิทธิ์ไม่สำเร็จ: ' || sqlerrm);
end $$;


-- ═══ 4. ประวัติการแก้ไข บันทึกการเปลี่ยนสลิปด้วย ═══════════════
-- ไม่มีบรรทัดนี้ = เปลี่ยนสลิปแล้วไม่มีร่องรอย ซึ่งขัดกับที่ทั้งระบบทำมา
-- เก็บ path จริงไว้ในประวัติ ส่วนหน้าเว็บแสดงเป็น "แนบไฟล์แล้ว" ให้อ่านง่าย

do $$
begin
  create or replace function public.log_txn_edit()
  returns trigger
  language plpgsql
  security definer
  set search_path = public
  as $f$
  declare ch jsonb := '[]'::jsonb;
  begin
    if new.ts        is distinct from old.ts        then ch := ch || jsonb_build_object('field','ts',       'from', old.ts::text,  'to', new.ts::text);  end if;
    if new.name      is distinct from old.name      then ch := ch || jsonb_build_object('field','name',     'from', old.name,      'to', new.name);      end if;
    if new.cat       is distinct from old.cat       then ch := ch || jsonb_build_object('field','cat',      'from', old.cat,       'to', new.cat);       end if;
    if new.method    is distinct from old.method    then ch := ch || jsonb_build_object('field','method',   'from', old.method,    'to', new.method);    end if;
    if new.method_to is distinct from old.method_to then ch := ch || jsonb_build_object('field','method_to','from', old.method_to, 'to', new.method_to); end if;
    if new.kind      is distinct from old.kind      then ch := ch || jsonb_build_object('field','kind',     'from', old.kind,      'to', new.kind);      end if;
    if new.amt       is distinct from old.amt       then ch := ch || jsonb_build_object('field','amt',      'from', old.amt::text, 'to', new.amt::text); end if;
    if new.code      is distinct from old.code      then ch := ch || jsonb_build_object('field','code',     'from', old.code,      'to', new.code);      end if;
    if new.flag      is distinct from old.flag      then ch := ch || jsonb_build_object('field','flag',     'from', old.flag,      'to', new.flag);      end if;
    if new.who       is distinct from old.who       then ch := ch || jsonb_build_object('field','who',      'from', old.who,       'to', new.who);       end if;
    if new.slip      is distinct from old.slip      then ch := ch || jsonb_build_object('field','slip',     'from', old.slip,      'to', new.slip);      end if;
    if new.void_at   is distinct from old.void_at   then ch := ch || jsonb_build_object('field','void',
      'from', case when old.void_at is null then '' else 'ยกเลิก · ' || old.void_reason end,
      'to',   case when new.void_at is null then '' else 'ยกเลิก · ' || btrim(new.void_reason) end); end if;

    if jsonb_array_length(ch) > 0 then
      insert into public.txn_edits (txn_id, edited_by, changes)
      values (old.id, coalesce(public.my_name(), '?'), ch);
    end if;
    return new;
  end $f$;
exception when others then
  insert into _v4_log values (4, 'อัปเดต trigger ไม่สำเร็จ: ' || sqlerrm);
end $$;


-- ═══ 5. บอก PostgREST ให้โหลด schema ใหม่ ══════════════════════
-- ถ้าลืมข้อนี้ หน้าเว็บจะยิงหาคอลัมน์ slip แล้วได้ 400 ทั้งที่คอลัมน์มีแล้ว

notify pgrst, 'reload schema';


-- ═══ ผลลัพธ์ — ดูตารางนี้ตารางเดียวพอ ═══════════════════════════
-- อ่านจาก catalog จริง ไม่ใช่จากที่ไฟล์นี้อ้างว่าทำอะไรไป

select 1 as "ข้อ", 'คอลัมน์ txns.slip' as "สิ่งที่ต้องมี",
       case when exists (select 1 from information_schema.columns
                          where table_schema = 'public' and table_name = 'txns' and column_name = 'slip')
            then '✓ มีแล้ว' else '✗ ยังไม่มี' end as "สถานะ",
       coalesce((select detail from _v4_log where step = 1), '—') as "ต้องทำอะไรต่อ"
union all
select 2, 'ถัง slips (ปิดสาธารณะ)',
       case when exists (select 1 from storage.buckets where id = 'slips' and public = false)
            then '✓ มีแล้ว' else '✗ ยังไม่มี' end,
       coalesce((select detail from _v4_log where step = 2), '—')
union all
select 3, 'สิทธิ์ถัง (อ่าน+อัป เท่านั้น)',
       case when (select count(*) from pg_policies
                   where schemaname = 'storage' and tablename = 'objects'
                     and policyname in ('slips_read', 'slips_insert')) = 2
            then '✓ ตั้งแล้ว' else '✗ ยังไม่ได้ตั้ง' end,
       coalesce((select detail from _v4_log where step = 3), '—')
union all
select 4, 'trigger บันทึกการเปลี่ยนสลิป',
       case when exists (select 1 from pg_proc
                          where proname = 'log_txn_edit'
                            and pronamespace = 'public'::regnamespace
                            and pg_get_functiondef(oid) like '%''field'',''slip''%')
            then '✓ บันทึกแล้ว' else '✗ ยังไม่ได้' end,
       coalesce((select detail from _v4_log where step = 4), '—')
order by 1;
