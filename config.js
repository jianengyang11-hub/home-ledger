// ─────────────────────────────────────────────────────────────
// ตั้งค่าเชื่อมต่อฐานข้อมูล Supabase
//
// 1. ไปที่ https://supabase.com  →  สร้าง project ใหม่ (ฟรี)
// 2. เข้า Project Settings → Data API
//      - "Project URL"  → เอามาใส่ SUPABASE_URL
// 3. เข้า Project Settings → API Keys
//      - "anon / public" → เอามาใส่ SUPABASE_ANON_KEY
// 4. เข้า SQL Editor แล้วรัน SQL ในไฟล์ schema.sql
//
// หมายเหตุ: anon key เปิดเผยได้ (ออกแบบมาให้ฝังในหน้าเว็บ)
// แต่ห้ามเอา service_role key มาใส่ตรงนี้เด็ดขาด
// ─────────────────────────────────────────────────────────────

window.LEDGER_CONFIG = {
  SUPABASE_URL: "https://xhnuigcwbcycthqjgjzb.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_SWNfPO3Wn-GA3MzsILMltw__VbaGLf4",

  // บัญชีหลัก — บัญชีเดียวที่แก้ไข/ลบรายการของคนอื่นได้
  ADMIN_ID: "pin",
};
