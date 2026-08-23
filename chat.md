3 Giải Pháp Tối Ưu Quy Trình Cụ Thể
1. Nén Bộ Core Thành "System Blueprint Nhất Thể" (Pre-Compiled Single Core)
Vấn đề cũ: AI phải gọi tool view_file 5 - 7 lần để mở từng file lẻ (AGENT_CONSTITUTION.md, WORKFLOW_STANDARDS.md, HARNESS_PROTOCOL.md...). Mỗi lần mở file mất 2 - 5 giây và tốn token I/O.
Tối ưu:
File 

.agents/AGENTS.md
 được thiết kế làm Single Blueprint (khoảng 300 - 500 tokens), tích hợp sẵn:
10 Điều luật cốt lõi (AGENT_CONSTITUTION).
Quy trình 7 Phase tóm tắt (WORKFLOW_STANDARDS).
Quy tắc Blocker khi bị kẹt (HARNESS_PROTOCOL).
Kết quả: AI chỉ cần nạp AGENTS.md (hệ thống tự động inject, không tốn tool call) là nắm đủ 100% "Hệ điều hành" của toàn bộ 7 file core mà không cần mở thêm bất kỳ file core nào khác.
2. Phân Tách Core Theo Vai Trò (Phase-Aware Core Injection)
Mỗi Model trong vòng lặp chỉ cần phần Core phục vụ đúng nhiệm vụ của nó:

Vai trò	Giai đoạn	File Core CẦN nạp	File Core KHÔNG nạp (bỏ qua)
Executor Model (Viết code)	Phase 0 $\rightarrow$ Phase 4 (Orient, Plan, Execute, Verify)	Tasks_list.md (Spec task) + WORKFLOW_STANDARDS.md (Các bước thực thi)	REVIEW_PROTOCOL.md (chưa review nên không cần), GLOSSARY.md
Reviewer Model (Phản biện)	Phase 5 (Cognitive Review & Debate)	REVIEW_PROTOCOL.md (Checklist 6 điểm) + REVIEWER_PROMPT_TEMPLATE.md + Git Diff	PROJECT_BRIEF.md, TECH_CONTEXT.md (Reviewer chỉ soi bug logic và bảo mật trên diff)
Hiệu quả: Reviewer Model không bị loãng context bởi hàng nghìn dòng mô tả dự án; nó chỉ tập trung 100% vào checklist phản biện của REVIEW_PROTOCOL.md.
3. Tận Dụng Sức Mạnh Prompt Caching Cấp Task (Task-Bound Caching)
Khi bắt đầu một Task mới (ví dụ TASK-001), AI nạp bộ Core rút gọn ở bước đầu tiên.
Ở các bước tiếp theo (viết code, sửa lỗi unit test theo verify.py), toàn bộ phần Core và Spec của TASK-001 đã nằm sẵn trong RAM/Cache của LLM (Prompt Cache).
Kết quả: Các bước sau chạy gần như tức thì (2 - 5 giây) và chi phí token cho phần Core giảm tới 75% - 90% nhờ cơ chế tính giá Prompt Cache của các model hiện đại (Gemini 3.7 Flash, Claude Sonnet...).
📊 Bảng So Sánh Trước & Sau Khi Tối Ưu
Tiêu chí	Cách cũ (Đọc toàn bộ Core mỗi lượt)	Giải pháp mới (JIT + Pre-compiled Core)
Số lần gọi tool mở file Core	5 - 7 tool calls / lượt	0 tool calls (Core đã nén sẵn trong System Prompt)
Dung lượng Token Core nạp vào	~4,500 - 6,000 tokens	~350 - 500 tokens (Đủ 100% luật & 7 Phase)
Độ tuân thủ quy trình & phản biện	Cao (nhưng chậm)	Tuyệt đối (Executor nắm 7 Phase, Reviewer có Checklist riêng)
Tốc độ phản hồi mỗi bước	20s - 45s / bước	3s - 8s / bước (Tận dụng Prompt Cache)
Bạn thấy cấu trúc phân bổ này đã cân bằng hoàn hảo giữa độ tuân thủ quy chuẩn của AI và tốc độ / chi phí token chưa?

4:57 PM
giải pháp này ok, nhưng chỉ đang nói về core, còn các file trong context và runtime thì mỗi lượt gọi AI có nạp ko, nạp lúc nào. Ví dụ mỗi phiên cấp task, ví dụ task-01 thì nạp lưu cache các file nào, qua task nhỏ trong task-01 có cần nạp lại ko?
5:03 PM
Dưới đây là cơ chế phân bổ, nạp và lưu cache chi tiết cho các file trong context/ và runtime/ trong suốt vòng đời của 1 Task (ví dụ TASK-01 và các bước nhỏ bên trong nó):

🗺️ Tổng Quan: Vòng Đời Nạp & Cache Theo Từng Bước
text
┌────────────────────────────────────────────────────────────────────────────────────────┐
│ [BƯỚC 1: KHỞI ĐỘNG TASK-01]                                                            │
│  Nạp Spec TASK-01 (từ context/) + Đọc TECH_CONTEXT.md + Tạo PLAN.md (vào runtime/)     │
│  ──► GHI TOÀN BỘ VÀO PROMPT CACHE CỦA TASK-01                                          │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [BƯỚC 2: CÁC BƯỚC NHỎ TRONG TASK-01] (Step 1.1 ──► Step 1.2 ──► Step 1.3)              │
│  • context/ : KHÔNG ĐỌC LẠI (Tận dụng 100% Prompt Cache có sẵn)                        │
│  • runtime/ : Chỉ nhận DIFF từ verify.py ──► Ghi đè PLAN.md / STATUS.md ra đĩa cứng   │
├────────────────────────────────────────────────────────────────────────────────────────┤
│ [BƯỚC 3: TASK-01 HOÀN TẤT ──► CHUYỂN SANG TASK-02]                                     │
│  • FLUSH MEMORY: Xóa sạch phiên chat TASK-01                                           │
│  • NẠP MỚI: Trích Spec TASK-02 + Tạo PLAN.md mới cho TASK-02                          │
└────────────────────────────────────────────────────────────────────────────────────────┘
📂 1. Khi Bắt Đầu Cấp Task (Ví Dụ: Bắt Đầu TASK-01)
Khi mở phiên làm việc cho TASK-01, hệ thống nạp các file sau vào bộ nhớ cache:

Nhóm	Tên File	Cơ Chế Nạp & Cache
context/	Tasks_list.md	Script chỉ trích xuất đúng đoạn Spec của TASK-01 đưa vào prompt (không nạp toàn bộ danh sách các task khác).
context/	TECH_CONTEXT.md & BOUNDARIES.md	Nạp 1 lần đầu để AI biết Tech Stack, thư viện và danh sách file cấm sửa.
context/	PROJECT_BRIEF.md	Chỉ nạp nếu task yêu cầu bối cảnh nghiệp vụ tổng thể.
runtime/	STATUS.md	Đọc trạng thái khởi đầu của task.
runtime/	PLAN.md	AI tạo mới PLAN.md chia nhỏ TASK-01 thành 3 - 5 bước atomic (ví dụ: Step 1.1: Tạo Model, Step 1.2: Viết Logic, Step 1.3: Viết Unit Test).
💾 Thiết lập Cache: Toàn bộ thông tin trên được cố định vào Prompt Cache của Session TASK-01.

⚡ 2. Khi Chạy Các Bước Nhỏ Atomic Bên Trong TASK-01 (Ví dụ: Từ Step 1.1 qua Step 1.2)
Khi AI làm xong Step 1.1 và chuyển sang Step 1.2:

❓ Có cần nạp lại các file trong context/ không?
KHÔNG CẦN NẠP LẠI!
Toàn bộ TECH_CONTEXT.md, BOUNDARIES.md và Spec của TASK-01 đã nằm sẵn trong Prompt Cache của phiên chat. AI chỉ việc tiếp tục suy luận từ bộ nhớ đệm mà không tốn 1 ms đọc lại file từ đĩa.
🔄 Các file trong runtime/ được xử lý thế nào?
Đầu vào mỗi bước nhỏ (Input):
Script chạy python3 pipeline/scripts/verify.py $\rightarrow$ Chỉ gửi báo cáo ngắn gọn VERIFICATION_REPORT.md (PASS hay FAIL dòng nào) vào ngữ cảnh.
Đầu ra mỗi bước nhỏ (Output — State Externalization):
AI thực hiện code xong, tự động GHI ĐÈ ra đĩa cứng:
Đánh dấu tick [x] Step 1.1 trong file pipeline/docs/runtime/PLAN.md.
Append 1 dòng nhật ký vào pipeline/docs/runtime/PROGRESS_LOG.md (ví dụ: 2026-08-23: Done model schema).
Cập nhật tiến độ Phase: EXECUTING trong pipeline/docs/runtime/STATUS.md.
🔄 3. Khi TASK-01 Hoàn Thành ([x] DONE) Và Chuyển Sang TASK-02
Flush Memory (Làm sạch bộ nhớ cũ):
Toàn bộ lịch sử hội thoại, các biến tạm, code nháp của TASK-01 được xóa sạch khỏi bộ nhớ RAM của AI.
Điều này triệt tiêu 100% hiện tượng "nhầm lẫn biến/code của task 1 sang task 2".
Nạp mới cho TASK-02:
Tasks_list.md $\rightarrow$ Trích xuất Spec MỚI của TASK-02.
PLAN.md $\rightarrow$ Reset và lập kế hoạch mới cho TASK-02.
Bắt đầu chu trình Cache mới cho TASK-02.
🎯 Tóm Tắt Tối Ưu:
context/: Nạp 1 LẦN DUY NHẤT khi mở Task $\rightarrow$ Giữ trong Prompt Cache xuyên suốt tất cả các bước nhỏ của task đó $\rightarrow$ Không đọc lại.
runtime/: Là "bảng nháp ghi nhận tiến độ ra đĩa cứng". AI đọc và cập nhật liên tục sau mỗi bước nhỏ để nếu gặp sự cố sập nguồn/reset, tiến độ không bao giờ bị mất.