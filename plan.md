# SPEC: Xây dựng Agent Pipeline riêng
### Tổng hợp bài học từ Anthropic Engineering Blog (Building Effective Agents 2024 + Scaling Managed Agents 2026) + Phản biện đối chiếu thực tế 2026

> Tài liệu này dùng để đưa cho một AI Agent (hoặc kỹ sư) làm kim chỉ nam khi thiết kế và triển khai một agent pipeline sản xuất (production-grade). Đã lọc bỏ các điểm lập luận yếu/sai giữa hai bộ phản biện trước đó, chỉ giữ lại phần đã được kiểm chứng hợp lý.

---

## 1. Mục tiêu tài liệu

Trả lời 3 câu hỏi cho người sắp xây pipeline:
1. **Nguyên tắc thiết kế nào nên giữ** từ tài liệu gốc của Anthropic.
2. **Pipeline được cấu thành từ những thành phần kỹ thuật nào** (không chỉ là "một bộ docs cho agent đọc" — đó chỉ là 1 trong nhiều lớp).
3. **Specs cụ thể** để một AI agent hỗ trợ dựng phần khung (scaffolding) ngay được.

---

## 2. Bài học cốt lõi đã lọc (giữ lại phần đúng, loại bỏ phần sai/quá cực đoan)

### 2.1 Giữ lại — đã kiểm chứng đúng
| # | Bài học | Vì sao giữ |
|---|---|---|
| 1 | **Bắt đầu đơn giản, chỉ tăng độ phức tạp khi đo được lợi ích** | Nguyên tắc kỹ thuật phần mềm phổ quát, không lỗi thời. |
| 2 | **Đừng hard-code giả định về giới hạn hiện tại của model** | Bitter Lesson — hạ tầng nên tách rời khỏi hành vi model tại 1 thời điểm, vì model sẽ tiến bộ nhanh hơn hạ tầng bạn xây. |
| 3 | **Tách "brain – hands – session" thành 3 interface độc lập** | Pattern ảo hoá/decoupling kinh điển, giúp scale, debug, bảo mật độc lập từng lớp. |
| 4 | **Đầu tư vào Agent-Computer Interface (ACI)** như đầu tư vào UX — đặt tên tool rõ ràng, ép định dạng chặt (VD: absolute path), test bằng nhiều input thực tế | Vẫn là yếu tố quyết định chất lượng agent nhiều hơn cả prompt tổng thể. |
| 5 | **Container/sandbox nên là "cattle" chứ không phải "pet"** | Giúp giảm TTFT, tránh phải "cứu sống" tiến trình lỗi, dễ scale ngang. |
| 6 | **Credential/token phải tách khỏi sandbox chạy code không tin cậy** | Nguyên tắc an ninh cơ bản — giảm bề mặt tấn công khi có prompt injection. |
| 7 | **Không dùng framework nặng khi task đơn giản; nhưng dùng chuẩn mở (MCP) và orchestration engine đã kiểm chứng khi cần quản lý trạng thái dài hạn** | Bản thân Anthropic cũng phải xây MCP + Managed Agents — chứng minh "tự viết từ đầu mãi mãi" không scale được ở production thực tế. |
| 8 | **Đo TTFT (time-to-first-token) như một chỉ số UX riêng biệt**, không chỉ đo latency tổng | Phản ánh đúng cảm nhận người dùng hơn. |

### 2.2 Loại bỏ / hiệu chỉnh — vì lập luận yếu hoặc không còn chính xác
| # | Điểm gốc | Vì sao loại/hiệu chỉnh |
|---|---|---|
| 1 | *"execute(name,input) → string là nút thắt vì ép mọi thứ về text, không hỗ trợ multimodal"* | **Sai một phần**: tool_result trong API hiện đại đã hỗ trợ content block đa phương thức (ảnh...). Giải pháp "dùng reference/URI thay vì payload thô" mà chính lập luận này đề xuất thực chất **vẫn nằm gọn trong khuôn khổ string** — không phá vỡ abstraction ban đầu. → Hiệu chỉnh thành: *"string interface vẫn ổn, nhưng nội dung string nên là con trỏ/URI tới tài nguyên lớn, không nhồi payload thô vào context."* |
| 2 | *"Nên tự viết code gọi LLM API trực tiếp, tránh mọi framework"* (bài 2024) | Anthropic tự phủ nhận điều này trong chính bài 2026 (khuyên dùng Managed Agents/Agent SDK). → Hiệu chỉnh: framework tối giản/chuẩn mở là cần thiết ở quy mô production, framework nặng che giấu prompt mới là thứ cần tránh. |
| 3 | *"Reasoning nội tại của model thay thế hoàn toàn workflow bên ngoài"* | Quá cực đoan — workflow bên ngoài vẫn cần cho **determinism, audit, kiểm soát chi phí**, những thứ suy luận ẩn bên trong model không thể thay thế được (không unit-test được một chuỗi suy nghĩ ẩn). → Hiệu chỉnh: dùng reasoning nội tại cho phần mở (open-ended), dùng workflow cứng cho phần cần kiểm soát chặt (validation, ghi DB, giao dịch tiền). |
| 4 | *Các con số hiệu năng trong bài Managed Agents (giảm 60–90% TTFT) là chuẩn ngành* | Đây chỉ là so sánh nội bộ giữa kiến trúc mới và kiến trúc cũ của chính Anthropic, không phải benchmark với đối thủ. → Không dùng làm mốc tham chiếu tuyệt đối, phải tự đo trên workload của bạn. |

---

## 3. Pipeline được cấu thành từ cái gì? (trả lời trực tiếp câu hỏi của bạn)

**Không phải chỉ là "một bộ docs để agent đọc và chạy theo".** Đó chỉ là 1 trong 6 lớp bắt buộc. Một agent pipeline production-grade gồm:

```
┌─────────────────────────────────────────────────────────┐
│  LỚP 1 — INSTRUCTION LAYER (docs tĩnh)                    │
│  System prompt, tool specs, style guide, playbook nghiệp vụ│
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  LỚP 2 — BRAIN / HARNESS (vòng lặp điều khiển)             │
│  Gọi model → nhận tool_use → route đến hands → lặp lại     │
│  Stateless, có thể chết và khởi động lại (wake/resume)     │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  LỚP 3 — SESSION / MEMORY (log sự kiện bền vững)           │
│  Event log tuần tự (ground truth) + Semantic index          │
│  (vector search / knowledge graph) để tránh "lost in middle"│
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  LỚP 4 — HANDS / TOOLS & SANDBOX                            │
│  execute(name, input) → string(hoặc content block)          │
│  MCP servers, sandbox thực thi code, API nội bộ/ngoài        │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  LỚP 5 — SECURITY & GOVERNANCE                              │
│  Vault credential tách khỏi sandbox, least-privilege scoping│
│  Guardrail/classifier, human-in-the-loop cho hành động rủi ro│
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  LỚP 6 — EVAL & OBSERVABILITY                                │
│  Tracing, logging từng tool call, bộ eval theo workload thật│
│  A/B test khi đổi model/harness, đo TTFT & tỷ lệ thành công   │
└─────────────────────────────────────────────────────────┘
```

**Docs tĩnh (Lớp 1) chỉ là "luật chơi" mô tả agent nên làm gì.** Phần "pipeline" thực sự nằm ở Lớp 2–6: đó là hệ thống phần mềm chạy vòng lặp, quản lý trạng thái, gọi tool, và tự phục hồi khi lỗi — không phải thứ agent "đọc rồi làm theo" một cách thụ động.

---

## 4. Nguyên tắc thiết kế cho từng lớp

### Lớp 1 — Instruction Layer
- Viết system prompt / tool docstring như viết tài liệu cho một junior dev: có ví dụ, edge case, ràng buộc rõ (VD: bắt buộc absolute path).
- Tách biệt: (a) playbook nghiệp vụ ổn định lâu dài, (b) style/format instructions, (c) safety/guardrail instructions — không gộp chung một khối văn bản khó bảo trì.
- Version hoá docs này giống code (Git), vì nó ảnh hưởng hành vi agent y hệt code.

### Lớp 2 — Brain/Harness
- Harness phải **stateless**: mọi trạng thái quan trọng nằm ở Session (Lớp 3), không nằm trong RAM của tiến trình harness.
- Thiết kế `wake(sessionId)` / `resume from last event` — nếu harness crash, khởi động lại tức thì mà không mất tiến độ.
- Chỉ thêm workflow cứng (chaining, routing, gate) ở những bước cần **determinism và audit** — không bọc toàn bộ luồng suy luận bằng workflow nếu model reasoning tự làm tốt hơn.

### Lớp 3 — Session/Memory
- Event log tuần tự là **nguồn sự thật duy nhất** (append-only, không sửa/xoá).
- Không nén/cắt ngữ cảnh một cách không thể đảo ngược — luôn giữ bản gốc, chỉ transform *khi đưa vào context window* của lượt gọi hiện tại.
- Thêm lớp semantic index (vector DB hoặc knowledge graph) song song với log tuần tự, để agent tìm lại thông tin theo **ý nghĩa** thay vì chỉ theo vị trí — tránh tốn turn dò tìm và giảm rủi ro "lost in the middle" khi phiên làm việc dài.

### Lớp 4 — Hands/Tools/Sandbox
- Chuẩn hoá tool interface qua **MCP** khi có thể, để không phải viết lại connector cho từng nguồn dữ liệu.
- Sandbox coi là tài nguyên dùng-một-lần: `provision({resources})` khi cần, hủy khi xong. Với tác vụ cần môi trường nặng (nhiều dependency), cân nhắc **warm-pool** (giữ sẵn vài instance ấm) để giảm cold-start, thay vì luôn khởi tạo từ đầu.
- Kết quả tool trả về nên gồm cả **content đa phương thức khi cần** (ảnh, dữ liệu có cấu trúc) và **reference/URI** cho payload lớn — tránh nhồi toàn bộ dữ liệu thô vào context.

### Lớp 5 — Security & Governance
- Credential không bao giờ đi vào sandbox nơi code không tin cậy chạy — dùng vault + proxy trung gian (giống mô hình OAuth-token-qua-proxy của Managed Agents).
- Áp dụng **least-privilege**: mỗi tool/session chỉ có đúng quyền cần cho tác vụ đó, không cấp quyền rộng "phòng khi cần".
- Với hành động **không thể hoàn tác** (xoá dữ liệu, chuyển tiền, gửi email ra ngoài, deploy production) — bắt buộc có bước xác nhận con người (human-in-the-loop), dù model có thông minh đến đâu. Đây là lớp phòng thủ chống prompt injection mà cô lập credential đơn thuần không giải quyết được.

### Lớp 6 — Eval & Observability
- Trace từng tool call (input/output/latency/lỗi) — đây là thứ thay thế việc "mở shell vào container để debug".
- Xây bộ eval **trên chính workload của bạn**, không tin số liệu benchmark của vendor (kể cả của Anthropic) là đại diện cho use case riêng.
- Đo và theo dõi: tỷ lệ thành công tác vụ, TTFT, chi phí token/tác vụ, tỷ lệ cần can thiệp con người — để biết khi nào nên tăng/giảm độ phức tạp của pipeline.

---

## 5. Checklist Specs — dùng để giao cho AI Agent hỗ trợ xây dựng

Khi đưa yêu cầu cho một AI agent (VD: Claude Code) để dựng khung pipeline, hãy cung cấp đủ các thông tin sau:

**A. Xác định phạm vi**
- [ ] Agent giải quyết bài toán gì? (coding, customer support, research, data ops...)
- [ ] Có cần multi-step dài hạn (long-horizon) hay chỉ 1–2 lượt gọi là xong?
- [ ] Task có thể đo thành công bằng gì (test tự động, review con người, metric nghiệp vụ)?

**B. Chọn kiến trúc theo độ phức tạp**
- [ ] Nếu task đơn giản, cố định → dùng **workflow** (chaining/routing), không cần agent tự chủ.
- [ ] Nếu task mở, không đoán trước được số bước → dùng **agent loop** với reasoning model.
- [ ] Nếu cần chạy dài hạn, nhiều phiên, cần resume → cần **Session layer** riêng biệt (đừng lưu state trong RAM harness).

**C. Hạ tầng tool/sandbox**
- [ ] Danh sách tool cần thiết, ưu tiên chuẩn MCP nếu có sẵn connector.
- [ ] Sandbox cần nặng (nhiều dependency) hay nhẹ? → quyết định cold-start on-demand hay warm-pool.
- [ ] Định dạng input/output của từng tool đã tối giản, tránh escaping phức tạp chưa (absolute path, JSON gọn, không ép nhồi payload lớn vào text)?

**D. Bảo mật**
- [ ] Credential nào cần thiết? Có tách khỏi sandbox chạy code không tin cậy chưa?
- [ ] Hành động nào là "không thể hoàn tác"? Đã gắn cơ chế xác nhận con người chưa?
- [ ] Có guardrail/classifier lọc output trước khi thực thi hành động rủi ro cao chưa?

**E. Memory & Context**
- [ ] Event log lưu ở đâu, có bền vững (durable) không?
- [ ] Có cần semantic search lại lịch sử phiên làm việc dài không, hay chỉ cần log tuần tự là đủ?

**F. Eval & Vận hành**
- [ ] Đã có bộ test case đại diện cho workload thật chưa?
- [ ] Có tracing cho từng tool call không?
- [ ] Có kế hoạch đo TTFT, chi phí/tác vụ, tỷ lệ can thiệp con người không?

---

## 6. Gợi ý công nghệ theo lớp (tham khảo, không bắt buộc)

| Lớp | Lựa chọn khởi điểm hợp lý | Khi nào cần nâng cấp |
|---|---|---|
| Brain/Harness | Claude Agent SDK, hoặc tự viết loop mỏng gọi trực tiếp API | Khi cần multi-brain, cần resume sau crash → cân nhắc Managed Agents/orchestration engine (Temporal) |
| Tool Integration | MCP server có sẵn (nếu có) | Khi cần connector tuỳ biến sâu cho hệ thống nội bộ |
| Sandbox | Container on-demand đơn giản | Khi cần cold-start nhanh → microVM (Firecracker/gVisor) hoặc warm-pool |
| Session/Memory | Database log tuần tự đơn giản (Postgres append-only) | Khi phiên làm việc dài, cần tìm lại theo ngữ nghĩa → thêm vector DB/knowledge graph |
| Security | Vault (VD: HashiCorp Vault, hoặc secret manager của cloud provider) + proxy token | Khi có nhiều tool/nhiều team → policy engine cho least-privilege tự động |
| Eval/Observability | Logging có cấu trúc + dashboard cơ bản | Khi scale → tracing chuyên dụng (OpenTelemetry) + bộ eval tự động chạy CI |

---

## 7. Lộ trình triển khai đề xuất (roadmap thực chiến)

1. **Tuần 1** — Định nghĩa 1 use case hẹp, đo được thành công rõ ràng. Viết Instruction Layer (Lớp 1) trước, test bằng tay qua workbench/console.
2. **Tuần 2** — Dựng Brain/Harness tối giản (loop gọi API trực tiếp), chưa cần Session layer riêng nếu task ngắn.
3. **Tuần 3** — Thêm Tool layer (MCP hoặc tool tự viết), áp dụng nguyên tắc ACI (absolute path, format gọn, tài liệu tool rõ ràng).
4. **Tuần 4** — Nếu task cần chạy dài/nhiều phiên: tách Session layer ra khỏi Harness, đảm bảo harness stateless, có thể resume.
5. **Tuần 5** — Thêm Security layer: vault credential, least-privilege, xác định danh sách hành động cần human-in-the-loop.
6. **Tuần 6** — Thêm Eval/Observability: tracing từng tool call, bộ test case thật, đo TTFT & tỷ lệ thành công.
7. **Liên tục** — Review lại các giả định cứng trong harness mỗi khi nâng cấp model (theo bài học #2 ở mục 2.1) — gỡ bỏ cơ chế vá lỗi hành vi cũ nếu model mới không còn mắc lỗi đó.

---

## 8. Nguyên tắc tối thượng cần nhớ

> **Đừng vá lỗi hành vi model bằng ràng buộc cứng trong hạ tầng — hãy tách hạ tầng khỏi hành vi model theo thời gian, và luôn tự đo trên workload thật của bạn thay vì tin số liệu benchmark của bất kỳ vendor nào, kể cả nhà cung cấp model bạn đang dùng.**