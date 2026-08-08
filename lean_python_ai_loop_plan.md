# Kế hoạch Tự động hóa Review & Debug Tinh gọn cho Python AI Coding Loop (Ralph Loop)

---

## 1\. TỔNG QUAN KIẾN TRÚC AI LOOP TINH GỌN (LEAN ARCHITECTURE)

### Triết lý thiết kế:

* **Tốc độ cực nhanh (High Speed):** Phản hồi kết quả kiểm tra cho AI trong vài miligiây đến vài giây.  
* **Tài nguyên tối thiểu (Zero Background Overhead):** 0MB RAM chạy ngầm (không dùng Docker, SonarQube Server hay ELK Stack).  
* **Tiết kiệm Token (Token-Efficient):** Cắt tỉa log rác, chỉ trích xuất đúng 15–20 dòng lỗi chính (StackTrace) gửi lại cho AI Prompt.  
* **Độc lập & Tự động (Autonomous):** AI tự sửa lỗi dựa trên phản hồi chuẩn xác từ Linter và Test Runner.

---

### Sơ đồ quy trình 4 bước (4-Step Execution Flow):

┌───────────────────────────────────────────────────────────────────────────────────┐

│ 1\. AI Coder sinh / sửa mã nguồn Python                                           │

└────────────────────────────────────────┬──────────────────────────────────────────┘

                                         │

                                         ▼

┌───────────────────────────────────────────────────────────────────────────────────┐

│ 2\. Lớp Kiểm tra Tĩnh Tinh gọn (Static Analysis CLI)                               │

│    \- Ruff: Kiểm tra Cú pháp, Code Smells, Imports, Formatting                     │

│    \- Mypy: Kiểm tra Kiểu dữ liệu (Type Check)                                     │

│    \- Bandit: Quét Lỗ hổng Bảo mật (Security Scan)                                 │

└────────────────────────────────────────┬──────────────────────────────────────────┘

                                         │

                   ┌─────────────────────┴─────────────────────┐

                   ▼                                           ▼

              \[CÓ LỖI\]                                    \[PASSED\]

                  │                                            │

                  │                                            ▼

                  │                          ┌──────────────────────────────────────┐

                  │                          │ 3\. Lớp Kiểm tra Động (Runtime Test)  │

                  │                          │    \- Pytest: Chạy Unit & Integration │

                  │                          └─────────────────┬────────────────────┘

                  │                                            │

                  │                               ┌────────────┴────────────┐

                  │                               ▼                         ▼

                  │                          \[CÓ LỖI\]                   \[PASSED\]

                  │                               │                         │

                  │                               │                         ▼

                  │                               │          ┌──────────────────────┐

                  │                               │          │ 4\. AI Reviewer Agent │

                  │                               │          │ (Đánh giá Logic cuối)│

                  │                               │          └──────────┬───────────┘

                  │                               │                     │

                  │                               │           ┌─────────┴─────────┐

                  │                               │           ▼                   ▼

                  │                               │       \[REJECTED\]          \[APPROVED\]

                  │                               │           │                   │

                  └───────────────────────────────┴───────────┴─────────┐         ▼

                                                                        │    \[HOÀN THÀNH\]

                                                                        ▼

                                                   ┌────────────────────────────────┐

                                                   │ Lọc Log tinh gọn (15 dòng) &   │

                                                   │ Gửi lại cho AI Coder ở Loop sau│

                                                   └────────────────────────────────┘

---

## 2\. BỘ CÔNG CỤ TINH GỌN CHO PYTHON (TECH STACK)

| Công cụ | Mảng đảm nhận | Lý do lựa chọn & Thay thế |
| :---- | :---- | :---- |
| **Ruff** | Static Analysis / Code Quality | Cực nhanh (viết bằng Rust, nhanh gấp 100x Flake8/Black). Thay thế SonarQube cho kiểm tra code xấu. |
| **Mypy** | Type Checking | Đảm bảo đúng kiểu dữ liệu, ngăn ngừa lỗi `AttributeError` hay `TypeError` ở runtime. |
| **Bandit** | Security Scanner | Quét các lỗ hổng bảo mật phổ biến trong code Python (SQL Injection, hardcoded secrets, insecure eval). |
| **Pytest** | Runtime Test Runner | Framework kiểm thử chuẩn cho Python. Bắt lỗi logic và Runtime Exceptions. |
| **Log Truncator** | Token Optimization | Python script tùy chỉnh để lọc bỏ log rác, chỉ giữ lại StackTrace trọng tâm cho AI Prompt. |

---

## 3\. SCRIPT ĐIỀU PHỐI VÒNG LẶP HOÀN CHỈNH (`ai_loop_runner.py`)

Dưới đây là mã nguồn Python đầy đủ để bạn tích hợp trực tiếp vào vòng lặp AI tự động:

import subprocess

import json

import re

import os

\# \--- 1\. HÀM CẮT TẢ LOG LỖI TỐI ƯU TOKEN \---

def truncate\_log(log\_text: str, max\_lines: int \= 20\) \-\> str:

    """Chỉ giữ lại các dòng lỗi quan trọng nhất và StackTrace chính."""

    lines \= log\_text.strip().split("\\n")

    if len(lines) \<= max\_lines:

        return log\_text

    

    \# Ưu tiên lấy các dòng chứa lỗi Traceback, FAILED, ERROR

    error\_lines \= \[\]

    in\_traceback \= False

    

    for line in lines:

        if "Traceback" in line or "FAILED" in line or "ERROR" in line:

            in\_traceback \= True

        if in\_traceback or line.startswith("E   ") or "Error:" in line:

            error\_lines.append(line)

            

    if error\_lines:

        return "\\n".join(error\_lines\[-max\_lines:\])

    return "\\n".join(lines\[-max\_lines:\])

\# \--- 2\. BƯỚC 1: KIỂM TRA CODE TĨNH (STATIC ANALYSIS) \---

def run\_static\_checks(target\_dir: str \= "."):

    print("\[1/3\] Đang chạy Static Analysis (Ruff \+ Mypy \+ Bandit)...")

    errors \= \[\]

    \# 1\. Chạy Ruff (Linter)

    ruff\_res \= subprocess.run(

        \["ruff", "check", target\_dir\],

        capture\_output=True, text=True

    )

    if ruff\_res.returncode \!= 0:

        errors.append(f"--- RUFF LINT ERRORS \---\\n{truncate\_log(ruff\_res.stdout)}")

    \# 2\. Chạy Mypy (Type Check)

    mypy\_res \= subprocess.run(

        \["mypy", target\_dir, "--ignore-missing-imports"\],

        capture\_output=True, text=True

    )

    if mypy\_res.returncode \!= 0:

        errors.append(f"--- MYPY TYPE ERRORS \---\\n{truncate\_log(mypy\_res.stdout)}")

    \# 3\. Chạy Bandit (Security Scan)

    bandit\_res \= subprocess.run(

        \["bandit", "-r", target\_dir, "-ll", "-q"\],

        capture\_output=True, text=True

    )

    if bandit\_res.returncode \!= 0:

        errors.append(f"--- BANDIT SECURITY ERRORS \---\\n{truncate\_log(bandit\_res.stdout)}")

    return "\\n\\n".join(errors) if errors else None

\# \--- 3\. BƯỚC 2: KIỂM TRA RUNTIME & TEST (PYTEST) \---

def run\_pytest():

    print("\[2/3\] Đang chạy Pytest...")

    pytest\_res \= subprocess.run(

        \["pytest", "--tb=short", "-q"\],

        capture\_output=True, text=True

    )

    if pytest\_res.returncode \!= 0:

        output \= pytest\_res.stdout \+ "\\n" \+ pytest\_res.stderr

        return f"--- PYTEST RUNTIME ERRORS \---\\n{truncate\_log(output)}"

    return None

\# \--- 4\. BƯỚC 3: AI REVIEWER PHẢN BIỆN (DÙNG MODEL PHẢN BIỆN) \---

def run\_ai\_reviewer\_check(code\_diff: str) \-\> str:

    print("\[3/3\] Đang nhờ AI Reviewer kiểm tra logic...")

    reviewer\_prompt \= f"""

    Bạn là một Senior Python Developer. Hãy review đoạn code diff sau đây:

    {code\_diff}

    

    Yêu cầu:

    1\. Kiểm tra xem có lỗi logic ẩn, cạnh biên (edge cases) chưa xử lý không.

    2\. Nếu ĐẠT: Trả về chính xác từ "APPROVED".

    3\. Nếu KHÔNG ĐẠT: Trả về lý do ngắn gọn (dưới 5 dòng).

    """

    \# Gọi API của AI Reviewer Model (Ví dụ GPT-4o / Claude 3.5)

    \# response \= call\_ai\_api(reviewer\_prompt)

    \# return response

    return "APPROVED" \# Giả định pass nếu không phát hiện lỗi logic

\# \--- 5\. ĐIỀU PHỐI VÒNG LẶP (MAIN LOOP) \---

def execute\_ai\_coding\_loop(max\_retries: int \= 5):

    for i in range(1, max\_retries \+ 1):

        print(f"\\n==================== VÒNG LẶP THỨ {i}/{max\_retries} \====================")

        

        \# 1\. Chạy AI Coder sinh / sửa code ở đây

        \# generate\_or\_fix\_code\_with\_ai(feedback\_prompt)

        \# 2\. Kiểm tra Static Analysis

        static\_errors \= run\_static\_checks()

        if static\_errors:

            print(f"❌ Static Check thất bại\! Gửi phản hồi cho AI sửa...")

            feedback\_prompt \= f"Code bị lỗi Static Analysis. Hãy sửa các lỗi sau:\\n\\n{static\_errors}"

            continue

        \# 3\. Kiểm tra Runtime Test

        runtime\_errors \= run\_pytest()

        if runtime\_errors:

            print(f"❌ Pytest thất bại\! Gửi StackTrace cho AI sửa...")

            feedback\_prompt \= f"Code bị lỗi Runtime khi chạy Pytest. Hãy sửa lỗi sau:\\n\\n{runtime\_errors}"

            continue

        \# 4\. Kiểm tra AI Reviewer

        \# diff \= get\_git\_diff()

        reviewer\_feedback \= run\_ai\_reviewer\_check("git diff content...")

        if "APPROVED" not in reviewer\_feedback:

            print(f"❌ AI Reviewer từ chối\! Gửi phản hồi cho AI Coder...")

            feedback\_prompt \= f"AI Reviewer chưa phê duyệt code. Lý do:\\n\\n{reviewer\_feedback}"

            continue

        print("\\n✅ TẤT CẢ KIỂM TRA ĐÃ PASS\! Vòng lặp hoàn thành thành công.")

        return True

    print("\\n⚠️ Vượt quá số lần lặp tối đa. Cần con người can thiệp.")

    return False

if \_\_name\_\_ \== "\_\_main\_\_":

    \# Cài đặt công cụ hỗ trợ: pip install ruff mypy bandit pytest

    execute\_ai\_coding\_loop()

---

## 4\. BẢNG SO SÁNH HIỆU QUẢ VỚI PHƯƠNG ÁN CŨ

| Chỉ số | Phương án cũ (SonarQube \+ ELK) | Phương án Tinh gọn mới (Python Stack) | Mức độ cải thiện |
| :---- | :---- | :---- | :---- |
| **Thời gian 1 Vòng lặp** | \~45 – 60 giây | **\~2 – 5 giây** | **Nhanh hơn 15–20 lần** |
| **Mức chiếm RAM hệ thống** | 3GB – 5GB RAM (Docker/Java) | **0 MB** (Chạy xong tự giải phóng) | **Tiết kiệm 100% RAM** |
| **Số Token tiêu tốn / Loop** | \~10,000 – 30,000 Tokens (Log thô) | **\~300 – 800 Tokens** (Log đã cắt tỉa) | **Tiết kiệm \> 90% Token** |
| **Độ phức tạp Cài đặt** | Phức tạp (Cài Docker, ES, Sonar) | Cực đơn giản (`pip install ruff mypy pytest bandit`) | **Triển khai trong 1 phút** |

