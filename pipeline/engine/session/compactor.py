"""Log compactor and token optimizer for extracting essential tracebacks and error messages."""



def truncate_log(log_text: str, max_lines: int = 20) -> str:
    """Extract essential traceback lines and trim verbose output to save context tokens.

    Args:
        log_text: Full raw log output from linter, test runner, or command.
        max_lines: Maximum lines to retain.

    Returns:
        Truncated string focused on critical errors.
    """
    if not log_text or not log_text.strip():
        return ""

    lines: list[str] = log_text.strip().split("\n")
    if len(lines) <= max_lines:
        return log_text.strip()

    error_lines: list[str] = []
    in_traceback: bool = False

    for line in lines:
        if any(keyword in line for keyword in ["Traceback", "FAILED", "ERROR", "Error:", "CRITICAL"]):
            in_traceback = True
        if in_traceback or line.startswith(("E   ", "  File ")):
            error_lines.append(line)

    if error_lines:
        return "\n".join(error_lines[-max_lines:])

    # Fallback to the last max_lines if no traceback markers are identified
    return "\n".join(lines[-max_lines:])
