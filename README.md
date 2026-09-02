# บ้านเรา · Home Ledger

หน้าเว็บสรุปรายรับรายจ่ายของบ้าน — เข้าสู่ระบบด้วย PIN, ภาพรวมรายเดือน, สรุปรายปี,
รายการทั้งหมด, บันทึกข้อมูล และมุมมองมือถือ รองรับภาษาไทย / ลาว

## เปิดดูแบบ local

เป็นเว็บ static ล้วน ต้องเสิร์ฟผ่าน HTTP (เปิดไฟล์ตรง ๆ ด้วย `file://` จะไม่ทำงาน):

```powershell
cd "C:\JIA\สรุปลายรับลายจ่าย"
python -m http.server 8765
# แล้วเปิด http://localhost:8765/
```

## โครงไฟล์

| ไฟล์ | หน้าที่ |
| --- | --- |
| `index.html` | หน้าแรก — redirect ไป `Home Ledger.dc.html` |
| `Home Ledger.dc.html` | ตัวเว็บทั้งหมด (Claude Design canvas) |
| `support.js` | runtime ที่ render `<x-dc>` โหลด React 18 UMD จาก unpkg |
| `_ds/industry-.../` | design system: `styles.css` + `_ds_bundle.js` |
| `.nojekyll` | จำเป็นสำหรับ GitHub Pages — ไม่งั้นโฟลเดอร์ `_ds` จะถูก Jekyll ข้าม |

## Deploy บน GitHub Pages

1. สร้าง repo ใหม่ (ชื่อเป็นอักษรอังกฤษ เช่น `home-ledger`)
2. อัปโหลดไฟล์ทั้งหมดในโฟลเดอร์นี้ **รวมถึง `.nojekyll` และโฟลเดอร์ `_ds`**
3. Settings → Pages → Source: `Deploy from a branch` → branch `main`, folder `/ (root)`
4. รอสักครู่ แล้วเปิด `https://<username>.github.io/home-ledger/`

## ข้อจำกัด

ตอนนี้ตัวเลขทั้งหมดเป็นข้อมูลตัวอย่างที่ hardcode ไว้ในไฟล์ ยังไม่มีฐานข้อมูล —
กดเพิ่มรายการแล้วข้อมูลจะไม่ถูกบันทึกถาวร และปิดหน้าเว็บแล้วค่าจะกลับไปเป็นค่าเริ่มต้น
