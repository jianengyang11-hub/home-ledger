-- ─────────────────────────────────────────────────────────────
-- Home Ledger — upgrade v3  ·  รันทีเดียวจบ
--
-- วิธีใช้: Supabase → SQL Editor → New query → Ctrl+A → วางทั้งไฟล์ → Run
-- ต้องรัน schema.sql, fix_txn_edits.sql, upgrade_v2.sql มาก่อนแล้ว
-- รันซ้ำได้ ไม่พัง
--
-- สิ่งที่ทำ
--   1. กันยอดยกมาใส่ซ้ำ — (บัญชี · ช่องทาง · สกุลเงิน) มียอดยกมาที่ใช้อยู่ได้แถวเดียว
--   2. ผูก txns.who เข้ากับ profiles.name — ใส่ชื่อที่ไม่มีอยู่จริงไม่ได้อีก
--
-- สองข้อนี้แยกกันเด็ดขาด ข้อไหนติดปัญหาก็ล้มเฉพาะข้อนั้น อีกข้อยังติดตั้งได้ตามปกติ
-- (แต่ละข้อห่อด้วย exception ของตัวเอง ไม่ลาก transaction ทั้งไฟล์ลงไปด้วย)
--
-- **ตารางผลลัพธ์ท้ายไฟล์คือสิ่งเดียวที่ต้องดู** — อ่านสถานะจาก catalog จริง
-- ไม่ใช่จากที่ไฟล์นี้อ้าง ถ้าขึ้น ✓ ทั้งสองแถว = จบ ปิดได้เลย
-- ถ้ามีแถวไหนขึ้น ✗ ช่อง "ต้องทำอะไรต่อ" จะบอกไว้ว่าติดตรงไหน id อะไรบ้าง
-- ─────────────────────────────────────────────────────────────


-- ═══ 0. ที่เก็บผลระหว่างทาง ════════════════════════════════════

drop table if exists _v3_log;
create temp table _v3_log (step int primary key, detail text);


-- ═══ 1. กันยอดยกมาใส่ซ้ำ ═══════════════════════════════════════
-- ยอดยกมาที่ใส่ซ้ำจะบวกเข้ายอดคงเหลือทุกครั้ง ได้ตัวเลขที่ดูปกติแต่ผิด
-- แยกตามสกุลด้วย เพราะช่องทางเดียวอาจมีเงินสองสกุล และระบบนี้ไม่แปลงค่าข้ามสกุล
-- นับเฉพาะแถวที่ยังไม่ถูกยกเลิก — ยกเลิกแถวเก่าแล้วใส่ใหม่จึงยังทำได้ตามปกติ

do $$
declare dup text;
begin
  select string_agg(d.txt, '   ·   ' order by d.txt) into dup
  from (
    select format('%s / %s / %s = %s แถว (id %s)',
                  t.who, t.method, t.code, count(*),
                  string_agg(t.id::text, ',' order by t.id)) as txt
      from public.txns t
     where t.kind = 'opening' and t.void_at is null
     group by t.who, t.method, t.code
    having count(*) > 1
  ) d;

  if dup is not null then
    insert into _v3_log values (1,
      'มียอดยกมาซ้ำค้างอยู่ก่อนแล้ว จึงยังสร้างกฎไม่ได้ → ' || dup ||
      '   ·   วิธีแก้: เปิดหน้า "รายการทั้งหมด" กดยกเลิกแถวที่เกิน ให้เหลือช่องทางละ 1 แถว แล้วรันไฟล์นี้ใหม่');
    return;
  end if;

  drop index if exists public.txns_opening_unique;
  create unique index txns_opening_unique
    on public.txns (who, method, code)
    where kind = 'opening' and void_at is null;

exception when others then
  -- เช่น ยังไม่ได้รัน upgrade_v2.sql เลยไม่มีคอลัมน์ void_at
  insert into _v3_log values (1, 'ติดตั้งไม่สำเร็จ: ' || sqlerrm);
end $$;


-- ═══ 2. ผูกชื่อบัญชีเข้ากับ profiles ═══════════════════════════
-- who เป็น text ลอย ๆ ใส่ชื่ออะไรก็ได้ เปลี่ยนชื่อใน profiles แล้วรายการเก่าค้างชื่อเดิม
-- กลายเป็นของคนที่ไม่มีอยู่จริง — กรองไม่เจอ และเจ้าของตัวจริงแก้รายการเก่าไม่ได้ (RLS)
--
-- on update cascade  เปลี่ยนชื่อใน profiles แล้วรายการเก่าตามไปเองทั้งหมด
-- on delete restrict ลบคนที่ยังมีรายการค้างไม่ได้ (รวมถึงลบ user ใน Authentication)
--
-- ไม่แตะ void_by กับ txn_edits.edited_by โดยตั้งใจ — สองช่องนั้นบันทึกว่าตอนนั้นใครทำ
-- เป็นประวัติ ไม่ใช่เจ้าของรายการ เปลี่ยนชื่อทีหลังจึงต้องไม่ตามไปแก้

do $$
declare orphan text;
begin
  select string_agg(d.txt, '   ·   ' order by d.txt) into orphan
  from (
    select format('%s = %s รายการ (id %s)',
                  t.who, count(*), string_agg(t.id::text, ',' order by t.id)) as txt
      from public.txns t
     where not exists (select 1 from public.profiles p where p.name = t.who)
     group by t.who
  ) d;

  if orphan is not null then
    insert into _v3_log values (2,
      'มีรายการที่ชื่อบัญชีไม่ตรงกับใครใน profiles จึงยังผูกไม่ได้ → ' || orphan ||
      '   ·   วิธีแก้ ก. สะกดต่างกันเฉย ๆ: update public.txns set who = ''ชื่อที่ถูก'' where who = ''ชื่อที่ผิด'';' ||
      '   ·   วิธีแก้ ข. ควรมีคนนี้จริง: ไปสร้าง user แล้วรัน schema.sql บล็อก 5 ให้ profiles ครบก่อน');
    return;
  end if;

  alter table public.txns drop constraint if exists txns_who_fkey;
  alter table public.txns
    add constraint txns_who_fkey
    foreign key (who) references public.profiles(name)
    on update cascade
    on delete restrict;

exception when others then
  insert into _v3_log values (2, 'ติดตั้งไม่สำเร็จ: ' || sqlerrm);
end $$;


-- ═══ 3. บอก PostgREST ให้โหลด schema ใหม่ ══════════════════════

notify pgrst, 'reload schema';


-- ═══ ผลลัพธ์ — ดูตารางนี้ตารางเดียวพอ ═══════════════════════════
-- อ่านจาก catalog จริง ไม่ใช่จากที่ไฟล์นี้อ้างว่าทำอะไรไป

select 1 as "ข้อ",
       'กันยอดยกมาใส่ซ้ำ' as "กฎ",
       case when exists (select 1 from pg_indexes
                          where schemaname = 'public' and indexname = 'txns_opening_unique')
            then '✓ ติดตั้งแล้ว' else '✗ ยังไม่ได้ติดตั้ง' end as "สถานะ",
       coalesce((select detail from _v3_log where step = 1), '—') as "ต้องทำอะไรต่อ"
union all
select 2,
       'ผูกชื่อบัญชีกับ profiles',
       case when exists (select 1 from pg_constraint
                          where conname = 'txns_who_fkey'
                            and conrelid = to_regclass('public.txns'))
            then '✓ ติดตั้งแล้ว' else '✗ ยังไม่ได้ติดตั้ง' end,
       coalesce((select detail from _v3_log where step = 2), '—')
order by 1;
