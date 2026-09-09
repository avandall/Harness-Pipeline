# HARNESS PROTOCOL
# Giao thức Harness — Ralph Loop & Vòng lặp tự trị (Next-Gen 2026)

> **Trạng thái:** CORE (Fixed) | **Phiên bản:** 2.0 (Optimized for AGY Pro Quota)
> **Mã thoát & Điều kiện dừng:** Xem chi tiết tại `pipeline/docs/core/EXIT_CODES.md`.

---

## 1. Ralph Loop là gì?

> **"Mỗi iteration = một Task-Bound Session. Filesystem = bộ nhớ dài hạn. Git = lịch sử. BLOCKERS/ = phanh an toàn qua đêm."**

```
┌────────────────────────────────────────────────────────┐
│  LOOP:                                                 │
│  1. Pick next [ ] TODO task from Tasks_list.md         │
│  2. JIT Context Injection (Task Spec + Tech + Scope)   │
│  3. Execute atomic steps (Plan → Execute → Verify)     │
│  4. Deterministic Verification: verify.py PASS 100%    │
│  5. Cognitive Review: git diff check (--review-model)  │
│  6. Auto-commit: [TASK-ID] feat/fix: description       │
│  7. Mark [x] DONE and Flush memory for next task       │
│  8. If stuck ≥ 2 times: [!] BLOCKED → Skip to next!    │
└────────────────────────────────────────────────────────┘
```

---

## 2. Quản Lý Ngữ Cảnh & Bộ Nhớ (Memory Management)

1. **Task-Bound Continuous Sessions:** Toàn bộ bước nhỏ trong 1 Task chạy trong 1 session liên tục để tận dụng 100% Prompt Caching.
2. **Flush Memory on Task Switch:** Bộ nhớ phiên được làm sạch hoàn toàn khi đổi sang Task mới để chống context drift.
3. **Context Pruning (JIT):** Chỉ inject đúng ~80 dòng tóm tắt cần thiết vào prompt đầu vào.
4. **Compaction Hard Stop (Exit 7):** Nếu hội thoại bị auto-compaction, script dừng khẩn cấp để yêu cầu chia nhỏ task.

---

## 3. Chế Độ Overnight Non-Blocking

Khi gặp blocker không thể tự giải quyết:
1. AI ghi chi tiết sự cố vào `pipeline/docs/runtime/BLOCKERS/<TASK_ID>.md`.
2. Đổi trạng thái dòng task trong `Tasks_list.md` thành `[!] BLOCKED`.
3. Giải phóng `STATUS.md`.
4. Vòng lặp tự động nhặt task `[ ] TODO` tiếp theo và tiếp tục chạy suốt đêm!

---

## 4. Dual-Model Mode (`--review-model`)

```bash
./pipeline/scripts/harness.sh --review-model gemini-3.6-flash-low
```
- **Executor:** Viết code, chạy `verify.py` pass 100%.
- **Reviewer:** Phản biện độc lập qua `git diff HEAD`. Tự động Auto-Approve nếu diff rỗng.
- **Commit:** Harness tự động commit Git khi Reviewer thông qua.

---

## 5. Bảng Mã Thoát POSIX (Tham chiếu `docs/core/EXIT_CODES.md`)
- `0`: Done (Toàn bộ hàng đợi hoàn tất)
- `3`: Blocked (Chế độ Strict Mode hoặc STOP.md)
- `4`: Max Iterations reached
- `6`: Stuck circuit breaker (Không có tiến độ commit)
- `7`: Context compaction hard stop
- `8`: Provider process / API failure
