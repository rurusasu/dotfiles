"""Skill health score calculation."""
import os


def get_config():
    """Load health score configuration from environment."""
    return {
        "window": int(os.environ.get("SKILL_HEALTH_WINDOW", "20")),
        "threshold": float(os.environ.get("SKILL_HEALTH_THRESHOLD", "0.7")),
        "correction_penalty": float(os.environ.get("SKILL_CORRECTION_PENALTY", "0.05")),
    }


def calculate_health_score(
    executions: list[dict],
    correction_count: int,
) -> float:
    """Calculate skill health score.

    score = success_rate - (correction_count * penalty)
    Clamped to [0.0, 1.0].

    Args:
        executions: List of recent executions with 'success' bool field.
        correction_count: Number of user correction feedbacks.

    Returns:
        Health score between 0.0 and 1.0.
    """
    config = get_config()

    if not executions:
        return 1.0

    recent = executions[-config["window"]:]
    success_count = sum(1 for e in recent if e.get("success", False))
    success_rate = success_count / len(recent)

    score = success_rate - (correction_count * config["correction_penalty"])
    return max(0.0, min(1.0, score))


def needs_improvement(score: float) -> bool:
    """Check if a skill's health score is below the improvement threshold."""
    config = get_config()
    return score < config["threshold"]
