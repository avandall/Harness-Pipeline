# 📖 CẨM NANG HƯỚNG DẪN SỬ DỤNG PIPELINE (NEXT-GEN HARNESS STANDARD)

> **Tài liệu hướng dẫn dành cho Human Developer & Harness Engineer (2026)**  
> Bộ khung làm việc tự động hóa cấp cao (Autonomous Ralph Loop & Multi-Tier Governance) tối ưu hóa riêng cho **Antigravity / Agy Pro Subscription Quota**.

---

## 1. Tổng Quan Kiến Trúc Pipeline

Pipeline giải quyết bài toán cốt lõi: **"Làm sao để AI làm việc qua đêm 100% tự động mà không bị drift, không ảo giác, không commit rác và tự học hỏi sửa sai sau mỗi chu kỳ?"**

Hệ thống được tổ chức theo mô hình **10 Bước Chuẩn Harness Engineering**:
1. **Brief & Clean Base**: Xác định rõ mục tiêu, truth và DoD (`PROJECT_BRIEF.md`).
2. **Master Router (< 100 dòng)**: Điều hướng tri thức JIT qua `AGENT_GUIDE.md` với bảng tra cứu Task-to-Guide và Precedence rules.
3. **Plan & Cryptographic Seal**: Khám phá và niêm phong kế hoạch bằng SHA-256 (`scripts/plan.sh seal`) chống drift mục tiêu.
4. **Frozen Visual/Functional Contracts**: Đo lường bằng chứng cụ thể thay vì tin vào cảm giác.
5. **Deterministic Verification (Tier 1)**: Đa ngôn ngữ (Python, TS/Node, Go, Shell) qua `verify.py`.
6. **Separation of Three Truths**: Tách biệt Plan Truth, Run Truth (bằng chứng/receipts) và Lifecycle Truth.
7. **Task-Bound State Machine**: Giữ 1 phiên liên tục cho 1 task (tối ưu Prompt Cache) và Flush Memory khi đổi task.
8. **Safe Loop & Discrete Exit Codes**: Mã thoát POSIX chuẩn (Chi tiết tại `docs/core/EXIT_CODES.md`).
9. **Zero-Token Offline Self-Tests**: Bộ kiểm thử phanh/hệ thống không tốn token (`scripts/selftest.sh`).
10. **Automated Retro & Self-Improvement**: Trích xuất lỗi tự động (`scripts/ralph-retro.sh`) và cập nhật ngược lại tài liệu/prompts qua `LEARNINGS.md`.

---

## 2. VAI TRÒ CỦA CON NGƯỜI (HUMAN-IN-THE-LOOP — HITL)

Trong kỷ nguyên 2026, **con người không ngồi gõ code từng dòng**, mà đóng vai trò là **Lead Architect & Người giám sát hệ thống**. Dưới đây là 3 thời điểm vàng bạn cần xuất hiện:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 👤 GIAI ĐOẠN 1: TRƯỚC KHI CHẠY (Pre-Loop: Định Hướng & Niêm Phong)     │
│    1. Điền sơ bộ Brief, Tech Context & Vùng Cấm (pipeline/docs/context)│
│    2. Chạy phản biện 2 model tự động hoàn thiện plan:                  │
│       ./pipeline/scripts/plan-refine.sh (hoặc chat phỏng vấn Mẹo 12).  │
│    3. Kiểm duyệt 100% DoD & Khóa niêm phong: ./scripts/plan.sh seal    │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Khởi động: ./harness.sh
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 🤖 GIAI ĐOẠN 2: TRONG KHI CHẠY (In-Loop: Tự Động 100% Qua Đêm)         │
│    • AI tự động: Plan ──► Code ──► verify.py ──► Review ──► Commit.    │
│    • BẠN RẢNH TAY HOÀN TOÀN (Đi ngủ hoặc làm việc khác).               │
│    • TỰ PHỤC HỒI SPEC NẾU LỆCH SEAL: Nếu AI sửa lén context, harness   │
│      tự tra Git history khôi phục lại context cũ và tiếp tục chạy.     │
│    ⚠️ XỬ LÝ BLOCKER (Nếu có):                                          │
│      Nếu AI kẹt 2 lần, nó tự ghi file docs/runtime/BLOCKERS/<TASK>.md   │
│      và tự nhảy sang task tiếp theo. Sáng dậy bạn đọc file giải đáp,   │
│      xóa file blocker và đổi status về [ ] TODO.                       │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Khi vòng lặp hoàn thành
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 👤 GIAI ĐOẠN 3: SAU KHI CHẠY (Post-Loop: Nghiệm Thu & Tự Học Hỏi)      │
│    1. Xem lịch sử git: git log --oneline                               │
│    2. Xem file bằng chứng: docs/runtime/PROOF_OF_SOLUTION.md          │
│    3. Cho AI tự học hỏi nâng cấp hệ thống: ./scripts/ralph-retro.sh    │
│    4. Yêu cầu phát sinh (nếu có): ./scripts/follow-up.sh "..."         │
└────────────────────────────────────────────────────────────────────────┘
```

### 🎙️ Hoàn Thiện Kế Hoạch Bằng Phỏng Vấn & Phản Biện 2 Giai Đoạn Tự Động (Mẹo 12 & 14)

Quy trình chuẩn mực để biến ý tưởng sơ bộ thành bản kế hoạch 100% không lỗ hổng, sẵn sàng chạy qua đêm:

```
┌────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ 1. Phỏng vấn với LLM   │ ───► │ 2. Dán nội dung vào     │ ───► │ 3. Chạy plan-refine.sh  │
│    (ChatGPT/Claude/Agy)│      │    INTERVIEW_PLAN.md    │      │    (Phản biện 2 giai đoạn)│
└────────────────────────┘      └─────────────────────────┘      └────────────┬────────────┘
                                                                              │
                                 ┌────────────────────────────────────────────┴────────────┐
                                 ▼                                                         ▼
                  ┌───────────────────────────────┐         ┌───────────────────────────────┐
                  │ Giai đoạn 1: Phản biện Kế hoạch│ ──PASS─►│ Giai đoạn 2: Phản biện Kỹ thuật │
                  │ (Lỗ hổng logic, edge cases,   │         │ (Atomic <=5-8 files, bottom-up│
                  │  giả định ngầm trong Plan)    │         │  dependencies, test gates TDD)│
                  └───────────────────────────────┘         └───────────────┬───────────────┘
                                                                            │ APPROVED
                                                                            ▼
                                                            ┌───────────────────────────────┐
                                                            │ Tự động seal & Chạy harness.sh│
                                                            └───────────────────────────────┘
```

#### Bước 1: Phỏng vấn nghiệp vụ với LLM (Prompt Mẫu)
Mở bất kỳ LLM nào (chat UI), copy prompt mẫu có sẵn tại đầu file `pipeline/docs/context/INTERVIEW_PLAN.md` để LLM phỏng vấn bạn, bóc tách bài toán và lên kế hoạch giải pháp sơ bộ.

#### Bước 2: Điền kế hoạch vào `pipeline/docs/context/INTERVIEW_PLAN.md`
Sao chép kết quả đã thống nhất vào cấu trúc chuẩn của `INTERVIEW_PLAN.md` (bao gồm cả các giả định ngầm hoặc điểm chưa chắc chắn để AI mổ xẻ).

#### Bước 3: Khởi chạy Vòng lặp Phản biện Tự động (`plan-refine.sh`)
```bash
./pipeline/scripts/plan-refine.sh
# Hoặc gọi nhanh qua:
./pipeline/scripts/plan.sh refine
```
Script sẽ khởi tạo tranh biện đối kháng giữa **Critic (Lead Architect)** và **Planner (System Architect)** theo 2 giai đoạn tuần tự:
- **Giai đoạn 1 (Bắt buộc làm trước): Phản biện Kế hoạch của User**: Critic đọc `INTERVIEW_PLAN.md`, soi từng lỗ hổng logic, kịch bản lỗi, giả định ngầm và tính khả thi kiến trúc. Nếu còn lỗ hổng, Critic REJECT ngay tại Giai đoạn 1 để Planner bổ sung hoàn thiện.
- **Giai đoạn 2 (Thực hiện sau): Phản biện Chi tiết Kỹ thuật**: Khi kế hoạch đã vững, Critic chuyển sang rà soát `Tasks_list.md` (kích thước task atomic <= 5-8 files, thứ tự phụ thuộc bottom-up, test strategy TDD Red-Green, cấu trúc bảng 7 cột).
- Toàn bộ tranh biện được ghi nhận tại `pipeline/docs/runtime/PLAN_DEBATE.md`.
- Khi cả 2 giai đoạn đạt 100%, script tự động commit context và niêm phong mật mã (`plan.sh seal`). Sẵn sàng chạy `./harness.sh`!

### 🔒 Chi Tiết Bước Niêm Phong Kế Hoạch & Tự Phục Hồi Context (Plan Sealing & Auto-Restore)
Sau khi có `Tasks_list.md`, bạn chạy lệnh trên terminal:
```bash
./pipeline/scripts/plan.sh seal
```
Lệnh này tính toán mã băm SHA-256 của các file context và lưu vào `docs/runtime/PLAN_SEAL.sha256`.  
- **Chuẩn hóa thông minh**: Checkbox trạng thái hoàn thành task (`[ ]` vs `[x] DONE`) được chuẩn hóa khi hash, do đó việc AI đánh dấu hoàn thành task **không** gây báo động giả.
- **Tự động khôi phục từ Git (Git Auto-Restore)**: Trong suốt quá trình chạy qua đêm, script `harness.sh` liên tục kiểm tra mã băm này. Nếu AI tự ý sửa lén spec, xóa bớt task hoặc làm trôi ranh giới (Specification Drift), `harness.sh` sẽ phát hiện cảnh báo, **tự động tìm trong lịch sử Git commit khớp với seal để khôi phục lại đúng context cũ** và tiếp tục chạy loop mà không dừng!

---

## 3. Cài Đặt Vào Dự Án Mới & Cơ Chế Override

### Cài đặt hoặc Cập nhật vào dự án mục tiêu:
```bash
# Cài đặt mới hoặc cập nhật hạ tầng (mặc định giữ nguyên PROJECT_BRIEF, Tasks_list của dự án cũ):
./pipeline/setup.sh /path/to/target-project

# Cập nhật ép buộc ghi đè toàn bộ kể cả context về template mẫu trắng:
./pipeline/setup.sh /path/to/target-project --override-all
```

#### 🔍 Cơ chế Ghi Đè (Override Logic) của `setup.sh`:
- **GHI ĐÈ 100% (Luôn cập nhật mới nhất):**
  - Toàn bộ scripts: `pipeline/scripts/*` (`harness.sh`, `verify.py`, `plan.sh`, `ralph-retro.sh`, `selftest.sh`...).
  - Router chính & Adapters: `pipeline/AGENT_GUIDE.md`, `.agents/AGENTS.md`, `CLAUDE.md`.
  - Hiến pháp & Giao thức: `pipeline/docs/core/*`, `docs/validation-status.md`.
  - Bộ Preset đa ngôn ngữ: `pipeline/presets/*`.
  - Wrapper ngoài root: `harness.sh`.
- **BẢO TỒN (Trừ khi có `--override-all`):**
  - Giữ nguyên các file nội dung riêng của dự án trong `pipeline/docs/context/` (`PROJECT_BRIEF.md`, `TECH_CONTEXT.md`, `BOUNDARIES.md`, `Tasks_list.md`) để bạn không bị mất dữ liệu task của dự án cũ!

---

## 4. Cấu Hình & Chọn Ngôn Ngữ Dự Án (Preset Matrix)

Mở `pipeline/presets/active_preset.yaml` để chọn môi trường kiểm thử:
- `python_backend`: Ruff + Mypy + Bandit + Pytest
- `node_react`: ESLint + TypeScript `tsc --noEmit` + Vitest/Jest
- `go_backend`: `golangci-lint` + `go vet` + `go test`
- `generic_scripting`: `shellcheck` cho Shell Scripts
- `polyglot_multi`: Tự động phát hiện và kiểm tra đồng thời tất cả ngôn ngữ trong dự án.

---

## 5. Bảng Tra Cứu Mã Thoát (Exit Codes Cheatsheet)
*(Chi tiết xem tại [`pipeline/docs/core/EXIT_CODES.md`](docs/core/EXIT_CODES.md))*

| Exit Code | Trạng Thái | Ý Nghĩa | Hành Động Xử Lý |
|---|---|---|---|
| `0` | **DONE** | Toàn bộ tasks trong queue đã verified pass 100% | Hoàn thành, sẵn sàng deploy |
| `3` | **BLOCKED** | Gặp phanh khẩn cấp (`STOP.md` hoặc `--stop-on-block`) | Đọc file blocker, giải quyết rồi xóa file để tiếp tục |
| `4` | **MAX_ITER** | Chạm giới hạn số vòng lặp tối đa | Tăng `--max-iter` nếu task cần thêm thời gian |
| `6` | **STUCK** | Circuit-breaker ngắt: Nhiều iteration không có commit | Thu hẹp task spec hoặc sửa prompt |
| `7` | **COMPACTION** | Context LLM bị auto-compaction mid-run | **Bắt buộc chia nhỏ task** để tránh sinh code suy thoái |
| `8` | **PROVIDER_FAIL**| Lỗi tiến trình CLI hoặc API 5xx lặp lại | Kiểm tra mạng hoặc quota nhà cung cấp |
