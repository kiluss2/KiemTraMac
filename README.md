# KiemTraMac: kiểm tra Mac cũ trước khi mua

Chạy trên máy định mua, khoảng 30 giây là có kết luận **✅ Nên mua / ⚠️ Ép giá / ⏸ Chưa mua được / ❌ Không nên mua**, kèm lý do từng dòng.
Tool chỉ **đọc** thông tin: không cài gì, không sửa gì, không gửi dữ liệu đi đâu.

Chạy được trên mọi máy Mac (Apple silicon và Intel) từ macOS 13 trở lên.

## Cách chạy (khuyên dùng)

Lệnh phải chạy **trên chính máy định mua**, không phải trên máy hay điện thoại của bạn.

1. Nếu bạn đang đọc trang này trên điện thoại hoặc máy khác: trên máy định mua, mở trình duyệt và vào **github.com/kiluss2/KiemTraMac**. Đang đọc trên máy định mua rồi thì bỏ qua bước này.
2. Bấm nút **copy** ở góc phải ô lệnh bên dưới, để khỏi phải gõ tay.
3. Mở **Terminal** (Cmd+Space, gõ `Terminal`, Enter), dán lệnh vào (Cmd+V) rồi nhấn Enter.

```bash
cd /tmp && curl -fsSL https://github.com/kiluss2/KiemTraMac/archive/refs/heads/main.tar.gz | tar xz && bash KiemTraMac-main/KiemTraMac.command
```

Tool hỏi 2 câu, đều có thể nhấn Enter để bỏ qua:
1. **Ngày mua** trên [checkcoverage.apple.com](https://checkcoverage.apple.com) (gõ serial vào để tra). Có ngày mua thì tool tính mức dùng và tuổi thọ còn lại chính xác hơn.
2. **Kiểm tra máy có thuộc công ty không** (Apple Business Manager). Bước này cần người bán nhập mật khẩu máy và có Internet.

## Cách khác: tải ZIP

Bấm **Code → Download ZIP**, giải nén, rồi nhấp đúp `KiemTraMac.command`.
Nếu macOS chặn: vào **System Settings → Privacy & Security**, kéo xuống, bấm **Open Anyway**.

## Tool kiểm tra những gì

| Nhóm | Nội dung |
|---|---|
| Khoá máy | Activation Lock, MDM, máy công ty (ABM), SIP |
| SSD | Độ mòn, dung lượng đã ghi, giờ hoạt động, lỗi dữ liệu, vùng dự phòng, quá nhiệt |
| Pin | Số lần sạc so với mức thiết kế, dung lượng còn lại so với chuẩn Apple |
| Độ ổn định | Số lần kernel panic (máy tự sập) trong 6 tháng |
| Mức dùng | So dung lượng ghi và số lần sạc mỗi năm với mốc chuẩn |
| Còn dùng được bao lâu | Dự kiến cho SSD, pin, và hỗ trợ macOS |
| Thông tin | Tên máy và năm ra mắt, cấu hình, serial, mã vùng (ví dụ `J/A` là bản Nhật) |

Cuối báo cáo có danh sách những mục phải tự kiểm tra bằng tay: màn hình, bàn phím, loa, các cổng, Parts & Service, và bước xoá máy để chắc chắn không còn khoá.

Báo cáo được lưu thành file `KetQua-<ngày giờ>.txt` cạnh tool.

## Lưu ý

- Các mốc "ít / bình thường / nhiều" được dựng từ dữ liệu đo thực tế và chuẩn pin của Apple. Không có tiêu chuẩn chính thức nào cho việc này.
- Thời điểm Apple ngừng hỗ trợ macOS cho từng đời máy chỉ là ước tính, vì Apple không công bố.
- Bước quyết định cuối cùng vẫn là: **Erase All Content and Settings → cài đặt đến bước Wi-Fi**. Máy không hỏi Apple ID của chủ cũ và không hiện "Remote Management" thì mới trả tiền.

## Thành phần

- `KiemTraMac.command`: script kiểm tra.
- `smartctl`: lấy từ [smartmontools](https://www.smartmontools.org) 7.5, không sửa mã nguồn, build lại dạng universal (Apple silicon và Intel) để chạy được từ macOS 13. Giấy phép GPL-2.0, xem `smartctl-LICENSE.txt`. Mã nguồn tại https://github.com/smartmontools/smartmontools/releases/tag/RELEASE_7_5
