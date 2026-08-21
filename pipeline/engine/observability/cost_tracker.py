"""Cost and Token Tracker for AI Agent interactions (Layer 6 - Observability)."""

from typing import Any, ClassVar


class CostTracker:
    """Tracks token usage and calculates estimated LLM API costs."""

    # Default pricing rates per 1,000 tokens ($)
    RATES: ClassVar[dict[str, dict[str, float]]] = {
        "gemini-3.6-flash": {"prompt": 0.0001, "completion": 0.0004},
        "claude-3-5-sonnet": {"prompt": 0.003, "completion": 0.015},
        "gpt-4o": {"prompt": 0.0025, "completion": 0.01},
    }


    def __init__(self):
        self.total_prompt_tokens: int = 0
        self.total_completion_tokens: int = 0
        self.total_cost_usd: float = 0.0

    def record_usage(self, model: str, prompt_tokens: int, completion_tokens: int) -> float:
        """Record token consumption and calculate incremental cost.

        Returns:
            Cost incurred in USD for this interaction.
        """
        rates = self.RATES.get(model.lower(), {"prompt": 0.001, "completion": 0.003})
        cost = (prompt_tokens / 1000.0) * rates["prompt"] + (completion_tokens / 1000.0) * rates["completion"]

        self.total_prompt_tokens += prompt_tokens
        self.total_completion_tokens += completion_tokens
        self.total_cost_usd += cost
        return round(cost, 6)

    def get_summary(self) -> dict[str, Any]:
        """Return cumulative token usage and cost stats."""
        return {
            "total_prompt_tokens": self.total_prompt_tokens,
            "total_completion_tokens": self.total_completion_tokens,
            "total_tokens": self.total_prompt_tokens + self.total_completion_tokens,
            "total_cost_usd": round(self.total_cost_usd, 6),
        }
