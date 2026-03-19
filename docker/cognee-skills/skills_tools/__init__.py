"""Skills tools package - registers custom MCP tools for skill improvement."""


def register_tools(mcp):
    """Register all skill improvement tools with the MCP server.

    Call this from server.py after FastMCP initialization:
        from skills_tools import register_tools
        register_tools(mcp)
    """
    from .log_execution import log_skill_execution_impl
    from .search_history import search_skill_history_impl
    from .skill_status import get_skill_status_impl
    from .improvements import get_skill_improvements_impl
    from .amend import amend_skill_impl
    from .evaluate import evaluate_amendment_impl
    from .rollback import rollback_skill_impl

    @mcp.tool(name="log_skill_execution", description="Log a skill execution result for tracking and improvement analysis.")
    async def log_skill_execution(skill_name: str, agent: str, task_description: str, success: bool, error: str = None, duration_ms: int = None):
        return await log_skill_execution_impl(skill_name, agent, task_description, success, error, duration_ms)

    @mcp.tool(name="search_skill_history", description="Search past skill execution history with optional filters.")
    async def search_skill_history(skill_name: str = None, agent: str = None, success: bool = None, limit: int = 20):
        return await search_skill_history_impl(skill_name, agent, success, limit)

    @mcp.tool(name="get_skill_status", description="Get the health status summary of a skill including success rate and failure patterns.")
    async def get_skill_status(skill_name: str):
        return await get_skill_status_impl(skill_name)

    @mcp.tool(name="get_skill_improvements", description="Generate improvement proposals for a skill based on failure patterns.")
    async def get_skill_improvements(skill_name: str, min_executions: int = 5):
        return await get_skill_improvements_impl(skill_name, min_executions)

    @mcp.tool(name="amend_skill", description="Apply a proposed skill amendment to the skill directory.")
    async def amend_skill(amendment_id: str):
        return await amend_skill_impl(amendment_id)

    @mcp.tool(name="evaluate_amendment", description="Evaluate whether an applied amendment improved the skill by comparing health scores.")
    async def evaluate_amendment(amendment_id: str):
        return await evaluate_amendment_impl(amendment_id)

    @mcp.tool(name="rollback_skill", description="Rollback a skill to its pre-amendment version if the amendment did not improve it.")
    async def rollback_skill(amendment_id: str):
        return await rollback_skill_impl(amendment_id)
