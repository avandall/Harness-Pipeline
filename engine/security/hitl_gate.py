"""Human-in-the-Loop Gate (Layer 5 - Security).

Intercepts high-risk or irreversible tool calls for human approval.
"""

from typing import List, Optional, Tuple


class HumanInTheLoopGate:
    """Interceptors for hazardous operations."""

    DEFAULT_HIGH_RISK_PATTERNS: List[str] = [
        "git push",
        "rm -rf",
        "DROP TABLE",
        "DELETE FROM",
        "deploy --prod",
        "systemctl restart",
    ]

    def __init__(self, high_risk_patterns: Optional[List[str]] = None):
        self.patterns: List[str] = high_risk_patterns or self.DEFAULT_HIGH_RISK_PATTERNS

    def inspect_action(self, tool_name: str, command: str) -> Tuple[bool, str]:
        """Check if an action is high-risk and requires human signoff.

        Returns:
            Tuple of (is_high_risk, reason)
        """
        for pattern in self.patterns:
            if pattern in command:
                return True, f"Command contains high-risk pattern: '{pattern}'"
        return False, "Action safe"
