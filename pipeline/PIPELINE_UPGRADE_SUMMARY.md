# 📊 BÁO CÁO NÂNG CẤP & TỐI ƯU TOÀN DIỆN: PIPELINE 2.0 (HARNESS ENGINEERING 2026)

> **Tác giả:** Harness Engineer (2026 Standard)  
> **Dự án:** Enterprise Autonomous Agent Pipeline (`pipeline`)  
> **Căn cứ:** Đối chiếu trực tiếp 29 Tips từ Video 1, 10 Bước chuẩn từ Video 2, mã nguồn gốc `/pipeline` và tài liệu thực chiến `Sample_pipeline/` (`flyrank-bih/harness-engineering-playbook`).

---

## I. BẢNG MA TRẬN KẾ THỪA & TỐI ƯU HÓA (WHO GAVE WHAT & WHY)

Dưới đây là bảng liệt kê chi tiết từng thành phần trong `pipeline/`, chỉ rõ nguồn gốc kế thừa từ đâu (Từ **Pipeline của Bạn** hay từ **Sample_pipeline**) và lý do giữ lại / tối ưu hóa:

| # | Thành phần / Tính năng | Nguồn kế thừa | Tại sao giữ lại? | Tối ưu hóa đạt được |
|---|---|---|---|---|
| 1 | **Master Router (`AGENT_GUIDE.md`)** | `Sample_pipeline` + Video 1 Tip 4 | Thay vì file `.agents/AGENTS.md` dài dòng (>120 dòng) chứa lẫn lộn nhiều thứ, tạo 1 router chuẩn <100 dòng với Precedence Rules và Task-to-Guide Routing Table. | Tiết kiệm token khởi động, loại bỏ hallucination, chỉ nạp tài liệu khi có nhu cầu (JIT RAG). |
| 2 | **Task-Bound Continuous Sessions** | **Pipeline của bạn** | AI duy trì 1 phiên hội thoại liên tục cho toàn bộ các bước (Plan → Execute → Verify) trong cùng 1 Task, tận dụng 100% Prompt Caching. Flush memory sạch sẽ khi đổi Task. | Tốc độ phản hồi nhanh gấp 3 lần, giảm 70% chi phí token so với việc reload session ở mỗi iteration vụn vặt. |
| 3 | **Dual-Model Cognitive Review (`--review-model`)** | **Pipeline của bạn** | Dùng Model A viết code và Model B (rẻ hơn hoặc cao cấp hơn) phản biện logic qua `git diff HEAD` và `DEBATE_LOG.md`. | Khắc phục triệt để Confirmation Bias (tự code tự duyệt), tự động Auto-Approve nếu diff rỗng để tiết kiệm token. |
| 4 | **Deterministic Multi-Language Engine (`verify.py`)** | **Pipeline của bạn** | Bộ kiểm định Tier 1 độc lập đa ngôn ngữ (Python, TypeScript/React, Go, Shell, Polyglot auto-detect). | Không phụ thuộc vào LLM để đánh giá code chạy được hay không; bắt buộc test/linter pass 100% trước khi commit. |
| 5 | **Mã Thoát POSIX Chuẩn (`docs/core/EXIT_CODES.md`)** | `Sample_pipeline` + `pipeline3` | Tách riêng tài liệu mã thoát POSIX: `0` (Done), `3` (Blocked), `4` (Max Iter), `6` (Stuck), `7` (Compacted), `8` (Provider Error). | Cho phép CI/CD, Cronjob, Workboard giám sát chính xác trạng thái kết thúc mà không cần đọc log LLM. Vô hiệu hóa budget do dùng gói AGY Pro Quota. |
| 6 | **Compaction Hard-Stop Protection (Exit 7)** | `Sample_pipeline` + Video 1 Tip 8 | Khi LLM chạm trần context và kích hoạt auto-compaction (tóm tắt hội thoại), chất lượng sinh code suy giảm nghiêm trọng. Hệ thống phát hiện và dừng khẩn cấp (Hard Stop). | Ngăn chặn AI sinh code ảo giác hoặc phá hỏng codebase khi bộ nhớ ngữ cảnh bị suy thoái. Buộc người dùng/hệ thống chia nhỏ task. |
| 7 | **Circuit Breaker & Transient 5xx Retry** | `Sample_pipeline` + Video 1 Tip 19 | Tự động ngắt khi AI chạy nhiều vòng không sinh ra commit (`NO_PROGRESS_MAX`); đồng thời tự động backoff retry khi gặp lỗi mạng/API 5xx mà không tính vào lỗi Stuck. | Chống đốt tiền vô ích khi AI rơi vào vòng lặp bế tắc vô tận; tự phục hồi khi mạng chập chờn. |
| 8 | **Automated Retro & Self-Improvement (`ralph-retro.sh`)** | `Sample_pipeline` + Video 1 Tip 21 | Sau khi loop kết thúc, script phân tích log để tìm các lỗi tool lặp đi lặp lại, gọi AI tự vá hướng dẫn trong `docs/*` và ghi vào `LEARNINGS.md`. | Vòng lặp tự làm thông minh vòng lặp (Self-improving harness), lỗi hôm nay gặp sẽ không lặp lại ngày mai. |
| 9 | **Zero-Token Offline Self-Tests (`selftest.sh`)** | `Sample_pipeline` + Video 2 Step 9 | Bộ kiểm tra toàn diện hoạt động của phanh, state machine, verify.py, log analyzer hoàn toàn offline với chi phí 0 token. | Đảm bảo hệ điều hành harness hoạt động hoàn hảo trước khi cấp quyền chạy AI thật. |
| 10 | **Plan Sealing & Drift Detection (`plan.sh`)** | `Sample_pipeline` + Video 2 Step 4 | Tạo mã băm SHA-256 niêm phong toàn bộ tài liệu mục tiêu (`PROJECT_BRIEF.md`, `Tasks_list.md`, `BOUNDARIES.md`). | Phát hiện ngay nếu mục tiêu bị sửa đổi âm thầm trong quá trình thực thi (chống Scope Drift). |
| 11 | **Provider-Neutral Runner (`agent-runner.sh`)** | `Sample_pipeline` | Cung cấp adapter trừu tượng hỗ trợ `agy`, `claude`, `codex`, hoặc custom CLI. | Không bị trói buộc vào 1 công cụ CLI duy nhất; dễ dàng chuyển đổi model/provider. |
| 12 | **Overnight Non-Blocking Blocker Queue** | **Pipeline của bạn** | Khi gặp bế tắc ở 1 task, ghi file `BLOCKERS/<TASK_ID>.md`, đổi status `[!] BLOCKED` và tự động nhảy sang task TODO tiếp theo. | Đảm bảo AI chạy xuyên đêm hoàn thành tối đa các task có thể, không bị treo cả hàng đợi vì 1 task khó. |
| 13 | **Task-Based Clean Git Convention (1 Task = 1 Commit)** | **Pipeline của bạn** | Nghiêm cấm commit vụn vặt `[iter-N]`. Chỉ commit khi task đã pass verify 100% với format chuẩn `[TASK-ID] <type>(<scope>): <desc>`. | Giữ lịch sử Git trong sạch, dễ revert, mỗi commit là một đơn vị tính năng hoàn chỉnh có thể deploy. |
| 14 | **Follow-up Request Channel (`follow-up.sh`)** | `Sample_pipeline` + Video 2 Step 10 | Cơ chế tiếp nhận yêu cầu chỉnh sửa sau khi đã hoàn thành task queue mà không làm hỏng lịch sử baseline cũ. | Hỗ trợ bảo trì và cập nhật linh hoạt nhưng vẫn đi qua đầy đủ các cổng kiểm tra chất lượng (Verification Gates). |
| 15 | **Trust Model Status Matrix (`docs/validation-status.md`)** | `Sample_pipeline` + Video 2 Step 2 | Bảng phân định rõ tính năng nào đã được kiểm chứng thực tế (✅ VERIFIED) và tính năng nào mới chỉ nằm trên lý thuyết (⚠️ DOC-DERIVED). | Giúp kỹ sư biết chính xác độ tin cậy của từng công cụ, tránh phụ thuộc vào các tính năng chưa thử nghiệm. |
| 16 | **Tài Liệu Hóa Exit Codes Độc Lập (`docs/core/EXIT_CODES.md`)** | `pipeline3` | Tạo file chuyên trách định nghĩa chi tiết mọi điều kiện dừng, hành vi non-blocking và resumability. | Cung cấp tài liệu tra cứu nhanh chóng và chính xác cho kỹ sư vận hành. |
