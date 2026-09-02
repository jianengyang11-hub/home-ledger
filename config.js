// ─────────────────────────────────────────────────────────────
// ตั้งค่าเชื่อมต่อ Supabase
//
// publishable key ปลอดภัยที่จะเปิดเผย — ออกแบบมาให้ฝังในหน้าเว็บ
// ตัวมันเองเปิดข้อมูลไม่ได้ ต้องล็อกอินก่อนถึงจะอ่าน/เขียนได้
// (RLS บังคับ `to authenticated` ไว้ทุกตาราง)
//
// ห้ามเอา service_role key มาใส่ตรงนี้เด็ดขาด
// ─────────────────────────────────────────────────────────────

window.LEDGER_CONFIG = {
  SUPABASE_URL: "https://xhnuigcwbcycthqjgjzb.supabase.co",
  SUPABASE_ANON_KEY: "sb_publishable_SWNfPO3Wn-GA3MzsILMltw__VbaGLf4",

  // ชื่อบัญชี → อีเมลที่ใช้ล็อกอิน (ต้องตรงกับที่สร้างใน Supabase → Authentication → Users)
  // ชื่อกับสิทธิ์ admin/member ตัวจริงอ่านจากตาราง profiles ในฐานข้อมูล
  // ตรงนี้เป็นแค่รายชื่อให้หน้า login แสดงเป็นปุ่มเลือกเท่านั้น
  ACCOUNTS: [
    { id: "pin",  name: "ปิ่น",    role: "บัญชีส่วนตัว",      email: "jianengyang11@gmail.com" },
    { id: "ton",  name: "ต้น",     role: "บัญชีส่วนตัว",      email: "jia@gmail.com" },
    { id: "home", name: "บ้านเรา", role: "บัญชีกลางของบ้าน", email: "yang11@gmail.com" },
  ],
};
