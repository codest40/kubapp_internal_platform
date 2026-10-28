"""
KUBAPP AI assessment client.
Provides a synchronous interface for KUBAPP CI code while communicating
with the assessment server through the MCP stdio transport.
"""

import asyncio
import json
import os
import sys
from pathlib import Path

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client


AI_DIR = Path(__file__).resolve().parent
SERVER_PATH = AI_DIR / "server.py"
ASSESSMENT_TOOL = "assess_artifact"
ASSESSMENT_TIMEOUT = 600.0
PROVIDER_ENV_VARS = (
    "LLM_PROVIDER",
    "OPENAI_MODEL",
    "OPENAI_API_KEY",
    "GOOGLE_MODEL",
    "GOOGLE_API_KEY",
    "OLLAMA_MODEL",
    "OLLAMA_HOST",
)
RECOMMENDATION_PRIORITIES = {"low", "medium", "high"}


class AIClientError(RuntimeError):
    """Raised when an MCP assessment request fails."""


def validate_request(request):
    """Validate the request envelope before sending it to MCP."""
    if not isinstance(request, dict):
        raise TypeError("Assessment request must be a dictionary.")

    context = request.get("context")
    rules = request.get("rules")

    if not isinstance(context, dict) or not context:
        raise ValueError(
            "Assessment request must contain a non-empty context."
        )

    if not isinstance(rules, dict) or not rules:
        raise ValueError(
            "Assessment request must contain a non-empty ruleset."
        )

    artifact_type = context.get("artifact_type")
    if not isinstance(artifact_type, str) or not artifact_type.strip():
        raise ValueError(
            "Assessment context must specify an artifact_type."
        )

    if rules.get("artifact_type") != artifact_type:
        raise ValueError(
            "Assessment context and ruleset artifact types do not match."
        )

    return {
        "context": context,
        "rules": rules,
    }


def validate_result(result):
    """Validate and preserve the complete assessment response."""
    if not isinstance(result, dict):
        raise AIClientError(
            "Invalid assessment response: expected a dictionary."
        )

    decision = result.get("decision")
    reason = result.get("reason")
    evidence = result.get("evidence")
    recommendations = result.get("recommendations")

    if type(decision) is not int or decision not in (0, 1):
        raise AIClientError(
            "Invalid assessment response: decision must be 0 or 1."
        )

    if not isinstance(reason, str) or not reason.strip():
        raise AIClientError(
            "Invalid assessment response: reason is required."
        )

    if (
        not isinstance(evidence, list)
        or not all(
            isinstance(item, str) and item.strip()
            for item in evidence
        )
    ):
        raise AIClientError(
            "Invalid assessment response: evidence must be "
            "a list of non-empty strings."
        )

    if not isinstance(recommendations, list):
        raise AIClientError(
            "Invalid assessment response: recommendations must "
            "be a list."
        )

    for index, recommendation in enumerate(recommendations):
        if not isinstance(recommendation, dict):
            raise AIClientError(
                "Invalid assessment response: recommendation "
                f"{index} must be a dictionary."
            )

        priority = recommendation.get("priority")
        action = recommendation.get("action")
        rationale = recommendation.get("rationale")

        if ( not isinstance(priority, str) or
             priority not in RECOMMENDATION_PRIORITIES ):
            raise AIClientError(
                "Invalid assessment response: recommendation "
                f"{index} has an invalid priority."
            )

        if not isinstance(action, str) or not action.strip():
            raise AIClientError(
                "Invalid assessment response: recommendation "
                f"{index} requires a non-empty action."
            )

        if not isinstance(rationale, str) or not rationale.strip():
            raise AIClientError(
                "Invalid assessment response: recommendation "
                f"{index} requires a non-empty rationale."
            )

    return {
        "decision": decision,
        "reason": reason,
        "evidence": evidence,
        "recommendations": recommendations,
    }


def parse_tool_result(tool_result):
    """Extract and decode the assessment returned by the MCP tool."""
    if getattr(tool_result, "isError", False):
        error_messages = [
            item.text.strip()
            for item in getattr(tool_result, "content", [])
            if getattr(item, "type", None) == "text"
            and isinstance(getattr(item, "text", None), str)
            and item.text.strip()
        ]

        detail = (
            "; ".join(error_messages)
            if error_messages
            else "No error details were provided."
        )

        raise AIClientError(
            f"The MCP assessment server reported a tool execution "
            f"error: {detail}"
        )

    structured_content = getattr(
        tool_result,
        "structuredContent",
        None,
    )

    if isinstance(structured_content, dict):
        return validate_result(structured_content)

    text_items = [
        item.text
        for item in getattr(tool_result, "content", [])
        if getattr(item, "type", None) == "text"
        and isinstance(getattr(item, "text", None), str)
    ]

    if not text_items:
        raise AIClientError(
            "The MCP assessment server returned no readable result."
        )

    if len(text_items) != 1:
        raise AIClientError(
            "The MCP assessment server returned an unexpected "
            "number of text results."
        )

    try:
        result = json.loads(text_items[0])
    except json.JSONDecodeError as exc:
        raise AIClientError(
            "The MCP assessment server returned invalid JSON."
        ) from exc

    return validate_result(result)


async def _mcp_entry(request):
    """Submit an assessment request through the MCP stdio transport."""
    if not SERVER_PATH.is_file():
        raise AIClientError(
            f"Assessment server was not found: {SERVER_PATH}"
        )

    # Explicitly forward only the configuration required by the provider.
    provider_env = {
        name: os.environ[name]
        for name in PROVIDER_ENV_VARS
        if name in os.environ
    }

    print(
        "[AI CLIENT DEBUG] Provider configuration:",
        {
            name: (
                provider_env.get(name)
                if name in (
                    "LLM_PROVIDER",
                    "OPENAI_MODEL",
                    "GOOGLE_MODEL",
                    "OLLAMA_MODEL",
                )
                else bool(provider_env.get(name, "").strip())
            )
            for name in PROVIDER_ENV_VARS
        },
        file=sys.stderr,
        flush=True,
    )

    server_parameters = StdioServerParameters(
        command=sys.executable,
        args=[str(SERVER_PATH)],
        cwd=str(AI_DIR.parent.parent),
        env=provider_env,
    )
    context = request.get("context")
    app_name = context.get("app_name")

    async with stdio_client(server_parameters) as (
        read_stream,
        write_stream,
    ):
        async with ClientSession(
            read_stream,
            write_stream,
        ) as session:
            print(
                f"[AI CLIENT] MCP initialization started for {app_name}",
                file=sys.stderr,
                flush=True,
            )
            await session.initialize()
            print(
                f"[AI CLIENT] MCP initialization completed for {app_name}",
                file=sys.stderr,
                flush=True,
            )

            print(
                f"[AI CLIENT] Tool discovery started for {app_name}",
                file=sys.stderr,
                flush=True,
            )
            available_tools = await session.list_tools()
            print(
                f"[AI CLIENT] Tool discovery completed for {app_name}",
                file=sys.stderr,
                flush=True,
            )

            tool = next(
                (
                    item
                    for item in available_tools.tools
                    if item.name == ASSESSMENT_TOOL
                ),
                None,
            )

            if tool is None:
                raise AIClientError(
                    "The MCP assessment server does not expose the "
                    f"required tool {ASSESSMENT_TOOL!r}."
                )

            print(
                f"[AI CLIENT] Assessment request started for {app_name}",
                file=sys.stderr,
                flush=True,
            )
            tool_result = await asyncio.wait_for(
                session.call_tool(
                    ASSESSMENT_TOOL,
                    {"request": request},
                ),
                timeout=ASSESSMENT_TIMEOUT,
            )
            print(
                f"[AI CLIENT] Assessment request completed for {app_name}",
                file=sys.stderr,
                flush=True,
            )
            return parse_tool_result(tool_result)


def mcp_entry(request):
    """
    Synchronous entry point used by scripts/ci/ai_analysis.py.
    Provider communication and assessment logic belong to the server.
    This function handles MCP transport and response validation only.
    """
    validated_request = validate_request(request)

    try:
        asyncio.get_running_loop()
    except RuntimeError:
        pass
    else:
        raise AIClientError(
            "mcp_entry() requires a synchronous execution context; "
            "it cannot run inside an active asyncio event loop."
        )

    try:
        return asyncio.run(_mcp_entry(validated_request))
    except AIClientError:
        raise
    except asyncio.TimeoutError as exc:
        raise AIClientError(
            "The MCP assessment request exceeded its time limit."
        ) from exc
    except Exception as exc:
        print(
            "[AI CLIENT ERROR] Full exception traceback:",
            file=sys.stderr,
            flush=True,
        )
        import traceback

        traceback.print_exception(
            type(exc),
            exc,
            exc.__traceback__,
            file=sys.stderr,
        )
        raise AIClientError(
            "MCP assessment communication failed. "
            "The artifact must not proceed."
        ) from exc
