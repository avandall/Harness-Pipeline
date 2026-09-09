# 🛑 EXIT CODES & LOOP STRATEGY

> **Authority: core.** Định nghĩa chính xác khi nào Ralph Loop dừng lại và mã thoát POSIX tương ứng.
> **Triết lý Harness Engineering:** *"A loop without explicit exits is a bill, not a harness."* Mọi điểm dừng phải có mã thoát chuẩn hóa và lý do rõ ràng.

---

## 1. Bảng Mã Thoát POSIX Chuẩn (Process Exit Codes)

| Mã Thoát | Trạng Thái | Điều Kiện Kích Hoạt | Ý Nghĩa Kỹ Thuật | Hành Động Xử Lý |
|---|---|---|---|---|
| `0` | **DONE** | Toàn bộ tasks trong queue đã `[x] DONE` hoặc `[!] BLOCKED` | Toàn bộ hàng đợi đã hoàn tất và kiểm chứng 100% | Thành công! Sẵn sàng nghiệm thu / deploy. |
| `3` | **BLOCKED** | Có `STOP.md` hoặc cờ `--stop-on-block` phát hiện blocker | Phanh khẩn cấp từ con người hoặc chế độ Strict Mode | Đọc file blocker trong `docs/runtime/`, giải quyết và xóa file để tiếp tục. |
| `4` | **MAX_ITER** | Vòng lặp vượt quá `MAX_ITERATIONS` (mặc định: 30) | Chạm trần an toàn số vòng lặp tối đa | Tăng `--max-iter` nếu task lớn cần thêm thời gian. |
| `6` | **STUCK** | `NO_PROGRESS_MAX` vòng liên tiếp không có git commit | Circuit-breaker ngắt mạch do AI rơi vào bế tắc | Thu hẹp phạm vi task, điều chỉnh prompt hoặc `git reset --hard`. |
| `7` | **COMPACTION**| CLI kích hoạt `compact_boundary` (tóm tắt ngữ cảnh) | Ngữ cảnh bị thoái hóa, AI bắt đầu có nguy cơ ảo giác | **Bắt buộc chia nhỏ task** thành các atomic sub-tasks nhỏ hơn. |
| `8` | **PROVIDER_FAIL**| Tiến trình CLI bị crash hoặc rớt mạng API 5xx lặp lại | Lỗi môi trường, process executor hoặc mạng | Kiểm tra kết nối mạng hoặc trạng thái CLI `agy`. |

> 💡 **Lưu ý về Ngân sách (Budget):** Hệ thống vận hành trên tài khoản **Antigravity / Agy Pro Subscription Quota**, không sử dụng pay-per-token API nên các hạn mức chi phí USD/Token đã được vô hiệu hóa để tối ưu hóa hiệu năng tối đa.

---

## 2. Phân Biệt: Blocked Cục Bộ (Overnight Mode) vs Blocked Toàn Bộ (Exit 3)

### A. Chế độ Mặc định: Overnight Non-Blocking (Không dừng tiến trình)
Khi AI gặp bế tắc ở một task cụ thể (sửa 2 lần không qua `verify.py` hoặc thiếu quyền):
1. AI ghi chi tiết sự cố vào: `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md`.
2. Đổi trạng thái dòng task trong `Tasks_list.md`: `[ ] TODO` ──► `[!] BLOCKED`.
3. Giải phóng `STATUS.md`.
4. `harness.sh` **TỰ ĐỘNG BỎ QUA VÀ CHUYỂN SANG TASK `[ ] TODO` TIẾP THEO!**
5. **Tiến trình KHÔNG DỪNG.** Vòng lặp tiếp tục chạy cho các task khác cho đến khi xong hết queue và trả về **Exit Code 0**.

### B. Chế độ Khẩn cấp / Nghiêm ngặt: Strict Mode (Exit Code 3)
Chỉ kích hoạt khi:
- Bạn chạy với cờ nghiêm ngặt: `./pipeline/scripts/harness.sh --stop-on-block`.
- Hoặc bạn chủ động tạo file phanh tay khẩn cấp: `touch pipeline/docs/runtime/STOP.md`.
- Khi đó, script sẽ dừng toàn bộ vòng lặp ngay lập tức và trả về **Exit Code 3**.

---

## 3. Khả Năng Phục Hồi & Tiếp Tục (Resumability)

Toàn bộ trạng thái của hệ thống được lưu trữ 100% trên đĩa (`docs/runtime/` + Git):
- Bạn có thể ngắt `harness.sh` bất kỳ lúc nào (`Ctrl + C` hoặc kill process).
- Khi gõ lại `./pipeline/scripts/harness.sh`, hệ thống tự động đọc lại đĩa và tiếp tục chính xác từ task đang dang dở mà không cần giải thích lại bối cảnh!
