import os
import sys
import json
import urllib.request
from pathlib import Path

API_KEY = os.environ.get("GEMINI_API_KEY", "")
URL = "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"

SYSTEM_CRITIC_PROMPT = """You are a Principal Agentic Engineer and Prompt Optimization Specialist applying Microsoft SkillOpt principles to autonomous coding agent prompts.

SkillOpt Core Principles:
1. Bounded & Precise Instructions: Minimize ambiguity, prevent LLM rambling or drift, enforce tight operational bounds.
2. Anti-Cheat & Deterministic Rigor: Explicitly forbid fake mocks, trivial bypasses (assert True), and unverified completion claims.
3. Resource & Scope Protection: Enforce strict file boundaries, prohibit background process wrapping for verification, require memory flush/state updates on disk.
4. Robust Failure Recovery: Ensure non-blocking failure protocols (blocker recording, fallback steps) rather than getting stuck in loops.
5. Strict Template Purity: Keep prompts as universal, generic templates. Never hardcode domain-specific logic, application names, or concrete programming language assumptions unless part of the standard template skeleton. Keep all template placeholders {{PLACEHOLDER}} intact.

Your task:
Analyze the input prompt, critique its operational loopholes or missing guardrails, and produce a hardened, production-grade, highly structured optimized markdown prompt.
Output strictly valid JSON with these keys:
{
  "critique": ["bullet 1", "bullet 2"],
  "key_improvements": ["improvement 1", "improvement 2"],
  "optimized_content": "Full markdown content of the optimized prompt"
}
"""

def optimize_prompt(file_path: Path):
    content = file_path.read_text(encoding="utf-8")
    user_prompt = f"Optimize this prompt from the enterprise autonomous harness pipeline:\nFile: {file_path.name}\n\n```markdown\n{content}\n```"

    payload = {
        "model": "gemini-2.5-flash",
        "messages": [
            {"role": "system", "content": SYSTEM_CRITIC_PROMPT},
            {"role": "user", "content": user_prompt}
        ],
        "response_format": {"type": "json_object"},
        "temperature": 0.2
    }

    req = urllib.request.Request(
        URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {API_KEY}"
        }
    )

    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        result_text = res["choices"][0]["message"]["content"]
        return json.loads(result_text)

if __name__ == "__main__":
    prompts_dir = Path("/home/avandall/project/boilerplate/pipeline/prompts")
    output_dir = Path("/home/avandall/project/boilerplate/pipeline/.ralph/optimized_prompts")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    report_file = output_dir / "OPTIMIZATION_REPORT.json"
    full_report = {}

    for prompt_file in sorted(prompts_dir.glob("*.md")):
        print(f"=== Optimizing {prompt_file.name} ===", flush=True)
        try:
            res = optimize_prompt(prompt_file)
            critique = res.get("critique")
            if isinstance(critique, list):
                critique_str = "; ".join(critique)
            else:
                critique_str = str(critique)
            print("  Critique:", critique_str[:120] + "...", flush=True)
            print("  Improvements:", len(res.get("key_improvements", [])), "items", flush=True)
            
            # Save candidate optimized prompt
            candidate_file = output_dir / f"optimized_{prompt_file.name}"
            candidate_file.write_text(res.get("optimized_content", ""), encoding="utf-8")
            full_report[prompt_file.name] = {
                "critique": res.get("critique"),
                "key_improvements": res.get("key_improvements")
            }
        except Exception as e:
            print(f"  Error on {prompt_file.name}: {e}", flush=True)

    report_file.write_text(json.dumps(full_report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nAll optimizations written to: {output_dir}", flush=True)
