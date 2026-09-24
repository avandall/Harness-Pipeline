# 🔍 HƯỚNG DẪN TRUY VẾT & GIÁM SÁT TIẾN TRÌNH HARNESS LOOP (LINUX / WSL)

Tài liệu này cung cấp toàn bộ các câu lệnh thực chiến để lập trình viên theo dõi tiến trình chạy ngầm, phát hiện nguyên nhân gây đơ/chậm (Dead Wait, treo lệnh shell, subprocess bị kẹt) và xử lý sự cố an toàn mà không làm gián đoạn cả hệ thống.

---

## 🏗️ 1. CÂY TIẾN TRÌNH HOẠT ĐỘNG NHƯ THẾ NÀO?

Khi bạn chạy `./pipeline/scripts/harness.sh`, mô hình phân cấp tiến trình diễn ra như sau:

```text
harness.sh (PID Cha điều phối loop)
 └── agent-runner.sh (PID wrapper)
      └── agy / claude (PID AI CLI Provider)
           └── Subprocess OS Commands (PID Con do AI tự gọi qua Tool)
                ├── python3 pipeline/scripts/verify.py
                │    ├── ruff check .
                │    ├── mypy .
                │    └── pytest ... (rất dễ bị Dead Wait nếu test suite quá lớn)
                ├── find / ... (NGUY HIỂM: Lệnh quét root gây treo toàn hệ thống)
                └── git status / git diff
```

> [!IMPORTANT]
> **Quy tắc vàng khi xử lý sự cố:**
> Khi AI bị đơ, **99% là do một Subprocess con ở tầng cuối cùng bị kẹt** (ví dụ `find /`, `pytest` dính lock DB). Bạn chỉ cần `kill -9` đúng PID của subprocess con đó, Agent cha (`agy`) sẽ ngay lập tức được giải phóng và tiếp tục làm việc!

---

## ⚡ 2. CÁC LỆNH TRUY VẾT NHANH (DIAGNOSTIC CHEAT-SHEET)

### A. Xem toàn bộ cây tiến trình của AI đang chạy
Lệnh này hiển thị quan hệ cha-con giữa các tiến trình để bạn nhìn thấy ngay Agent đang đẻ ra lệnh shell nào:

```bash
# Xem cây tiến trình của agy và các lệnh con đang chạy dưới nó
pstree -ap $(pgrep -f "agent-runner|agy" | head -1)

# Hoặc xem dạng cây toàn diện các tiến trình liên quan đến ralph/harness:
ps -ef --forest | grep -E "harness|agent|agy|python|pytest|find"
```

---

### B. Tìm các tiến trình "đáng ngờ" đang chạy quá lâu (Dead Wait)
Hiển thị PID, thời gian đã chạy thực tế (`etimes` tính bằng giây), thời gian CPU thực tế (`cputime`) và dòng lệnh:

```bash
# Liệt kê tất cả tiến trình liên quan kèm thời gian chạy
ps -eo pid,ppid,etimes,cputime,%cpu,%mem,cmd | grep -E "agy|verify|pytest|mypy|find|bandit" | grep -v grep
```

🔍 **Cách đọc kết quả:**
- Nếu cột `etimes` = 450 (đã chạy 7.5 phút) nhưng `cputime` = 00:00:01 (CPU chỉ tốn 1 giây):
  👉 **Tiến trình đang bị Dead Wait (nghẽn I/O, treo mạng hoặc treo ổ đĩa).**

---

### C. Bắt quả tang lệnh quét ổ đĩa root (`find /`)
Lệnh `find /` là thủ phạm số 1 khiến AI bị block đơ hàng chục phút:

```bash
# Kiểm tra xem có lệnh find / nào đang chạy ngầm không
pgrep -a find
# Hoặc
ps aux | grep "find /" | grep -v grep
```

---

### D. Kiểm tra tiến trình đang mở file gì hoặc đang kẹt ở đâu (`lsof`)

```bash
# Xem tiến trình có PID cụ thể đang đọc/ghi file nào
lsof -p <PID>

# Xem tiến trình con đang chiếm port mạng nào (nếu test microservices)
lsof -i -P -n | grep <PID>
```

---

### E. "Soi" trực tiếp tiến trình đang làm gì theo thời gian thực (`strace`)
Nếu thấy một lệnh Python hoặc shell chạy mãi không xong, hãy xem nó đang gọi system call gì:

```bash
# Xem trực tiếp từng thao tác OS của tiến trình <PID> (Ctrl+C để thoát xem)
strace -p <PID> 2>&1 | head -n 30
```
- Nếu output cuộn liên tục `openat(...)` hàng nghìn file Windows (`/mnt/c/...`): tiến trình đang quét nhầm ổ đĩa.
- Nếu output đứng yên ở `read(...)` hoặc `futex(...)`: tiến trình đang bị lock hoặc chờ socket mạng.

---

### F. Xem Log Trực Tiếp (Live Stream Logs)
Mở một cửa sổ terminal phụ để xem log trực tiếp mà không cần bấm lệnh liên tục:

```bash
# 1. Xem log tổng thể phiên chạy
tail -f pipeline/docs/runtime/session_live.log

# 2. Hoặc xem log thô của turn hiện tại (thay <RUN_ID> bằng thư mục mới nhất trong .ralph/runs/)
tail -f pipeline/.ralph/runs/$(ls -t pipeline/.ralph/runs/ | head -1)/iter-*-EXECUTOR.log
```

---

## 🛑 3. CÁC LỆNH XỬ LÝ SỰ CỐ & DỪNG TIẾN TRÌNH (KILLING & UNBLOCKING)

### Cấp độ 1: Giải cứu Agent bằng cách hủy ĐÚNG lệnh con bị treo (Khuyên Dùng)
Khi thấy lệnh `find /` hoặc `pytest` bị treo, **KHÔNG** được tắt cả terminal. Hãy hủy riêng lệnh con đó để Agent tự động nhận lỗi timeout/fail và chuyển sang bước tiếp theo:

```bash
# Hủy bằng PID cụ thể đã tìm thấy ở Bước 2
kill -9 <PID_CON>

# Hoặc hủy nhanh tất cả các lệnh find đang chạy ngầm
pkill -9 -f "find /"

# Hoặc hủy riêng pytest nếu test suite bị deadlock kết nối DB
pkill -9 -f "pytest"
```

---

### Cấp độ 2: Hủy toàn bộ turn của Agent (Bắt đầu lại turn kế tiếp)
Nếu Agent bị loạn ngữ cảnh hoặc treo hoàn toàn:

```bash
# Hủy tiến trình agy hiện tại (Harness sẽ tự động bắt đầu lượt kế tiếp với context recovery)
pkill -f "agy"
```

---

### Cấp độ 3: Dừng khẩn cấp toàn bộ hệ thống Harness (Emergency Stop)
Nếu bạn muốn dừng vòng lặp ngay lập tức và dọn dẹp sạch sẽ:

```bash
# 1. Tạo cờ dừng an toàn (Harness sẽ tự nhận diện và thoát êm ả)
touch pipeline/docs/runtime/STOP.md

# 2. Hoặc dừng cưỡng bức toàn bộ Harness và các tiến trình rác còn sót:
pkill -f "harness.sh"
pkill -f "agent-runner.sh"
pkill -f "ralph-managed-run"
```

---

## 📋 4. BẢNG TỔNG HỢP CÁC TRIỆU CHỨNG TIẾN TRÌNH KINH ĐIỂN

| Triệu chứng quan sát được | Nguyên nhân gốc rễ | Lệnh chẩn đoán | Lệnh xử lý ngay |
| :--- | :--- | :--- | :--- |
| **Harness im lặng > 10 phút, CPU 0%** | Agent gọi `find /` hoặc `grep -r /` quét qua ổ cứng Windows `/mnt/c` | `pgrep -a find` | `pkill -9 -f "find /"` |
| **Pytest chạy > 5 phút không nhả log** | Test case dính lock Database hoặc chờ socket mạng | `ps aux \| grep pytest` | `pkill -9 -f "pytest"` |
| **Mypy chạy quá lâu (> 3 phút)** | Mypy quét toàn bộ virtualenv hoặc thư mục lớn không exclude | `ps aux \| grep mypy` | `pkill -9 -f "mypy"` |
| **Git báo `fatal: index.lock exists`** | Turn trước bị kill đột ngột để lại lock file trong Git | `ls -la .git/index.lock` | `rm -f .git/index.lock` |


## 5. Others
### Cấp độ 1: Xem nhanh các log Iteration của một Run
Các log trực tiếp do harness ghi lại nằm trong pipeline/.ralph/runs/<RUN_ID>/:

# 1. Liệt kê các file trong run (chú ý cột dung lượng file)
ls -lh pipeline/.ralph/runs/20260923-212344/

# File nào ~80 - 120 bytes là bị TIMEOUT giữa chừng:
cat pipeline/.ralph/runs/20260923-212344/iter-1-EXECUTOR.log

# File nào > 2KB là lần chạy HOÀN THÀNH thành công:
cat pipeline/.ralph/runs/20260923-212344/iter-6-EXECUTOR.log

### Cấp độ 2: Xem toàn bộ suy nghĩ (Thinking) & Từng bước Agent đã làm (Transcript chi tiết)
agy CLI lưu lại 100% transcript (từng câu lệnh, từng đoạn code agent đọc/sửa, thời gian chạy từng giây) tại thư mục ~/.gemini/antigravity-cli/brain/:
# 1. Liệt kê các session gần nhất khớp với giờ chạy của harness:
ls -lt ~/.gemini/antigravity-cli/brain/ | head -n 10

# 2. Xem các bước cuối cùng trước khi session bị timeout (thay UUID bằng session bạn muốn xem):
tail -n 25 ~/.gemini/antigravity-cli/brain/1b55394e-3722-4916-a57c-a92c833697be/.system_generated/logs/transcript.jsonl | jq .

# 3. Xem danh sách tất cả các hành động mà agent đã thực hiện trong lượt đó:
grep -o '"toolAction":"[^"]*"' ~/.gemini/antigravity-cli/brain/1b55394e-3722-4916-a57c-a92c833697be/.system_generated/logs/transcript.jsonl


### Cấp độ 3: Xem lại code viết dở mà agent đã làm trước khi bị Harness reset
Khi harness dọn dẹp để chuẩn bị cho lượt sau, nó luôn cất code dở vào git stash:

# Xem danh sách các lần harness đã backup code dở:
git stash list

# Xem chi tiết code dở của lần gần nhất:
git stash show -p stash@{0}




