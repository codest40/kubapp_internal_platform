# KUBAPP CI — AI Assessment Client and MCP Transport

## Overview

`ai/client.py` provides the client-side interface between KUBAPP CI and the AI assessment server. It communicates with the server through the Model Context Protocol (MCP) using standard input/output (stdio) transport.

The client is responsible for validating requests, starting the assessment server, initializing the MCP session, discovering the required tool, submitting assessment requests, parsing responses, and enforcing a request timeout.

The main entry points and helpers are:

- `mcp_entry(request)` — synchronous interface used by `ai_analysis.py`.
- `_mcp_entry(request)` — asynchronous MCP communication implementation.
- `validate_request(request)` — validates the request envelope before communication.
- `parse_tool_result(tool_result)` — extracts and validates the server's response.
- `validate_result(result)` — validates the assessment result structure.
- `AIClientError` — exception type for client-side assessment and communication failures.

The client handles transport and response validation. The assessment logic and provider communication are delegated to the server.

## Assessment Server Configuration

The client defines the following configuration:

| Setting | Value or behavior |
|---|---|
| `AI_DIR` | Directory containing `client.py`. |
| `SERVER_PATH` | `server.py` in the same directory as `client.py`. |
| `ASSESSMENT_TOOL` | `assess_artifact`. |
| `ASSESSMENT_TIMEOUT` | 600 seconds. |
| `PROVIDER_ENV_VARS` | Explicit list of environment variables forwarded to the server. |

The server must exist at `SERVER_PATH`. If the file is missing, the client raises `AIClientError` before attempting to establish an MCP session.

The server is launched using the current Python interpreter:

`sys.executable`

Its working directory is set to `AI_DIR.parent.parent`, which resolves to the CI directory containing the `ai` package.

## Request Validation

Before starting the asynchronous communication flow, `mcp_entry()` calls `validate_request()`.

The request must be a dictionary containing:

- `context` — a non-empty dictionary.
- `rules` — a non-empty dictionary.

The context must include a non-empty string `artifact_type`, and the rules dictionary's `artifact_type` must match it.

The function returns a normalized envelope containing the original context and rules dictionaries.

This validation checks the request's basic structure and artifact-type consistency. It does not independently verify the full schema or semantics of every rule and context field.

The more detailed ruleset checks are performed by `ai_analysis.py` before it calls the client.

## Provider Environment Forwarding

The client explicitly constructs the environment passed to the assessment server.

The forwarded variables are:

| Variable | Purpose |
|---|---|
| `LLM_PROVIDER` | Provider selection. |
| `OPENAI_MODEL` | OpenAI model configuration. |
| `OPENAI_API_KEY` | OpenAI authentication credential. |
| `GOOGLE_MODEL` | Google model configuration. |
| `GOOGLE_API_KEY` | Google authentication credential. |
| `OLLAMA_MODEL` | Ollama model configuration. |
| `OLLAMA_HOST` | Ollama endpoint configuration. |

Only variables present in the parent process environment are included.

The resulting dictionary is passed to `StdioServerParameters` as the server environment. The code does not merge the entire parent environment into this dictionary.

This makes the forwarded configuration explicit, but it also means the server receives no other environment variables unless they are supplied through another mechanism.

### Provider Configuration Logging

Before launching the server, the client prints provider configuration diagnostics to standard error.

Provider selection and model names are logged as values. For the API-key variables and other settings outside that group, the diagnostic prints whether the value is non-empty rather than printing the value itself.

This avoids printing the configured API-key contents in this diagnostic message. It does not establish that credentials cannot appear in other logs or error messages elsewhere in the system.

## MCP Session Lifecycle

The asynchronous `_mcp_entry()` function manages the communication lifecycle.

### 1. Start the server

The client constructs `StdioServerParameters` using:

- The current Python executable.
- The absolute path to `server.py`.
- The configured working directory.
- The explicitly constructed provider environment.

### 2. Establish the stdio transport

The client opens the MCP stdio connection using `stdio_client()`.

This establishes the communication streams used by the client session.

### 3. Initialize the session

A `ClientSession` is created, and `session.initialize()` is called.

The client logs the start and completion of initialization.

### 4. Discover available tools

The client calls `session.list_tools()` and searches the returned tools for the exact name:

`assess_artifact`

If the server does not expose this tool, the client raises `AIClientError`.

The client does not select an alternative tool automatically.

### 5. Submit the assessment request

The client invokes the discovered tool with the request envelope:

```python
session.call_tool(
    "assess_artifact",
    {"request": request},
)
```

The tool invocation is wrapped in `asyncio.wait_for()` with a timeout of 600 seconds.

If the tool call exceeds that limit, the client raises a timeout error that is translated into `AIClientError` by `mcp_entry()`.

The timeout specifically wraps the tool invocation. It does not wrap the entire `_mcp_entry()` lifecycle, so server startup, MCP initialization, and tool discovery do not share one overall 600-second deadline.

### 6. Parse the response

Once the tool call returns, the client passes the result to `parse_tool_result()`.

The result is not accepted merely because the MCP call completed successfully. It must also satisfy the client's response-validation requirements.

## Response Parsing

`parse_tool_result()` supports two response formats.

### Structured response

If `structuredContent` is a dictionary, the client validates and returns it.

### Text response

If structured content is unavailable or is not a dictionary, the client examines text content blocks.

The text fallback requires exactly one readable text result. That text must contain valid JSON representing the assessment result.

The following conditions cause `AIClientError`:

- The MCP tool reports an execution error.
- No readable text result is available and no usable structured result exists.
- Multiple text results are returned instead of exactly one.
- The text result contains invalid JSON.
- The parsed result fails validation.

When the tool reports an error, the client collects non-empty text blocks from the tool response and includes them in the error detail when available.

## Assessment Result Validation

`validate_result()` requires a dictionary containing the following fields:

| Field | Validation |
|---|---|
| `decision` | Integer `0` or `1`; booleans are rejected. |
| `reason` | Non-empty string. |
| `evidence` | List of non-empty strings. |
| `recommendations` | List of recommendation dictionaries. |

Each recommendation must contain:

| Field | Validation |
|---|---|
| `priority` | One of `low`, `medium`, or `high`. |
| `action` | Non-empty string. |
| `rationale` | Non-empty string. |

The function returns a dictionary containing these four validated fields.

It does not preserve arbitrary additional fields from the server response. Ruleset metadata, artifact type, and application name are added later by `ai_analysis.py` when it constructs the normalized result for `KUBAPP_DECISION()`.

The validation confirms the response structure and allowed values, not the correctness of the AI's decision or evidence.

## Synchronous Entry Point

`mcp_entry(request)` provides a synchronous interface for callers such as `ai_analysis.py`.

It performs the following steps:

1. Validate the request.
2. Check whether the current thread already has a running asyncio event loop.
3. Reject execution if an event loop is already running.
4. Run `_mcp_entry()` using `asyncio.run()`.
5. Translate timeouts and unexpected communication errors into `AIClientError`.

The active-event-loop check prevents this synchronous wrapper from attempting to start another event loop in the same thread.

This interface is designed for synchronous CI execution. It is not intended to be called directly from an asynchronous function that is already running an event loop.

## Error Handling

The client uses `AIClientError` for assessment transport and response failures.

| Failure | Behavior |
|---|---|
| Invalid request envelope | Raises `TypeError` or `ValueError` before MCP communication. |
| Missing server file | Raises `AIClientError`. |
| Required tool not found | Raises `AIClientError`. |
| MCP tool reports an error | Raises `AIClientError` with available error details. |
| Missing, malformed, or invalid response | Raises `AIClientError`. |
| Tool call times out | Raises `AIClientError` indicating that the time limit was exceeded. |
| Unexpected communication exception | Logs the exception traceback to standard error and raises `AIClientError`. |
| Synchronous call made inside an active event loop | Raises `AIClientError`. |

The generic exception handler retains the original exception as the cause. This helps with debugging while presenting callers with a consistent client-level exception type.

The client does not convert an invalid or failed assessment into a passing decision.

## Integration with the KUBAPP Assessment Pipeline

The intended relationship between the assessment modules is:

```text
ai_analysis.py
      |
      | context + rules
      v
mcp_entry()
      |
      v
Validate request
      |
      v
Start server.py over MCP stdio
      |
      v
Initialize session and discover tool
      |
      v
Call assess_artifact
      |
      v
Parse and validate response
      |
      v
Return validated assessment fields
      |
      v
ai_analysis.py adds ruleset metadata
      |
      v
KUBAPP_DECISION()
      |
      +---- Pass: return report
      |
      +---- Reject: attempt report publication,
                    then raise an exception
```

The client does not itself decide whether an artifact should be rejected. It transports the request and validates the returned decision. `ai_analysis.py` normalizes the result, and `platform_decision.py` records and enforces it.

The complete fail-closed behavior depends on these layers being called in the intended order and on exceptions being allowed to prevent execution.

## Operational Considerations

### 1. Transport success is not assessment correctness

Successful MCP communication establishes that the client received and parsed a response. It does not prove that the underlying assessment is accurate or that the ruleset is sufficient.

### 2. The server process is launched for each client call

Each `_mcp_entry()` invocation constructs a new stdio server connection and session. The code does not maintain a persistent session across calls.

### 3. The timeout is scoped to the tool call

The 600-second limit applies to `session.call_tool()`, not to every stage from server startup through response parsing.

### 4. Provider configuration is explicitly scoped

The server receives the configured provider variables rather than the complete parent environment. Provider functionality depends on the necessary settings being present.

### 5. The client is not a sandbox

MCP stdio transport and response validation do not isolate the assessment server or the assessed artifact. Execution isolation belongs to separate parts of KUBAPP's CI architecture.

### 6. Error messages may contain server-provided details

When an MCP tool reports an error, the client incorporates available text details into its exception message. Those details should be handled appropriately by callers and logging systems.

## Scope and Limitations

`ai/client.py` is responsible for **MCP communication, provider-environment forwarding, request and response validation, timeout handling, and client-level error reporting**.

It does not:

- Generate the security rules.
- Implement the AI assessment logic itself.
- Independently verify the accuracy of the assessment.
- Persist assessment reports.
- Enforce the final decision against an artifact.
- Provide a sandbox for commands or scripts.
- Guarantee an overall timeout for the complete server and session lifecycle.

It serves as the communication boundary between KUBAPP's CI assessment code and the MCP assessment server.
