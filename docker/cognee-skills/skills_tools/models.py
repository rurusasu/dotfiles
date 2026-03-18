"""Custom DataPoint definitions for skill improvement graph."""
from datetime import datetime
from enum import Enum
from typing import Optional
from uuid import uuid4

from cognee.infrastructure.engine import DataPoint


class AmendmentStatus(str, Enum):
    PROPOSED = "proposed"
    APPLIED = "applied"
    ROLLED_BACK = "rolled_back"
    FAILED = "failed"


class FeedbackType(str, Enum):
    USER_CORRECTION = "user_correction"
    AUTO = "auto"


class Skill(DataPoint):
    __tablename__ = "skills"
    name: str
    source_path: str
    agent_type: str

    _metadata = {"index_fields": ["name"], "type": "Skill"}


class SkillVersion(DataPoint):
    __tablename__ = "skill_versions"
    skill_id: str
    version: int
    content: str
    content_hash: str
    created_at: datetime

    _metadata = {"index_fields": ["skill_id", "version"], "type": "SkillVersion"}


class Execution(DataPoint):
    __tablename__ = "executions"
    skill_id: str
    agent: str
    task_description: str
    success: bool
    error: Optional[str] = None
    duration_ms: Optional[int] = None
    timestamp: datetime

    _metadata = {"index_fields": ["skill_id", "agent", "success"], "type": "Execution"}


class Feedback(DataPoint):
    __tablename__ = "feedbacks"
    execution_id: str
    feedback_type: FeedbackType
    message: str
    timestamp: datetime

    _metadata = {"index_fields": ["execution_id"], "type": "Feedback"}


class Amendment(DataPoint):
    __tablename__ = "amendments"
    skill_id: str
    diff: str
    rationale: str
    status: AmendmentStatus = AmendmentStatus.PROPOSED
    score_before: Optional[float] = None
    score_after: Optional[float] = None
    version_before: Optional[int] = None
    version_after: Optional[int] = None
    created_at: datetime

    _metadata = {"index_fields": ["skill_id", "status"], "type": "Amendment"}
