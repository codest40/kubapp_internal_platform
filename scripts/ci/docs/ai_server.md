# KUBAPP CI — AI Assessment MCP Server

## Overview

`ai/server.py` implements KUBAPP's AI assessment server. It exposes an MCP tool named `assess_artifact`, accepts an artifact context and its associated security rules, dispatches the assessment to the configured AI provider, validates the model response, and returns a structured result to the CI client.

The server supports three provider backends:

- Ollama
- OpenAI
- Google Gemini

The module is responsible for assessment orchestration and provider communication. It does not execute submitted commands, scripts, or other artifacts.

## Server Configuration

The server defines the following primary settings:

| Setting | Value | Purpose |
|---|---|---|
| `SERVER_NAME` | `kubapp-ci-assessment` | MCP server identity. |
| `SERVER_VERSION` | `0.1.0` | MCP server version. |
| `REQUEST_TIMEOUT` | `600.0` seconds | HTTP request timeout configuration. |
| `MAX_RESPONSE_BYTES` | `1 MiB` | Maximum serialized assessment-request size. |
| `PROMPT_FILE` | `ai/prompts/assessment_message.txt` | System assessment instructions. |

The server uses `setup_provider.py` to resolve the configured provider, model, settings, and Ollama endpoint.

It runs through MCP stdio transport using `server.run_stdio_async()`.

## MCP Tool: `assess_artifact`

The server exposes one tool:

`assess_artifact(request: dict) -> dict`

The tool receives a request containing:

- `context` — the artifact and its execution-related information.
- `rules` — the security rules to apply to that artifact.

The tool validates the request, checks its serialized size, and passes the validated context and rules to `generate_assessment()`.

The request must be a dictionary containing non-empty dictionaries for both `context` and `rules`.

The context must specify a non-empty string `artifact_type`, and the ruleset's `artifact_type` must match it.

The ruleset must also contain:

- A non-empty `ruleset_id`.
- A non-empty `ruleset_version`.
- A non-empty list of non-empty string instructions.
- A dictionary-valued `response_schema`.

The server checks that `response_schema` is a dictionary but does not use that supplied schema directly to construct the provider request. Instead, it defines its own `RESPONSE_SCHEMA` for the Ollama and OpenAI requests and separately constructs a Google response schema.

### Input Size Limit

Before generating the assessment, the server serializes the complete request to JSON, encodes it as UTF-8, and checks the resulting byte length.

Requests larger than 1 MiB are rejected with `AssessmentError`.

This is an input-size check performed after the request has been received and parsed by MCP. It is not a transport-level limit that prevents the oversized request from reaching the server.

## Prompt Construction and Untrusted Artifact Data

The `build_messages()` function loads the system prompt from:

`ai/prompts/assessment_message.txt`

If the file cannot be read or its contents are empty, the server raises `AssessmentError`.

The server then creates a JSON payload containing the supplied rules and artifact context:

```python
user_payload = {
    "assessment_rules": rules,
    "untrusted_artifact_context": context,
}
```

This payload is serialized as JSON and included in the user message. The message explicitly instructs the model to treat values inside `untrusted_artifact_context` as data rather than instructions.

The messages sent to the provider have two roles:

| Role | Content |
|---|---|
| `system` | Instructions loaded from the assessment prompt file. |
| `user` | Assessment rules and serialized artifact context. |

This separation makes the intended trust boundary explicit. However, describing submitted artifacts as untrusted data does not, by itself, guarantee that a model will resist every prompt-injection attempt. The effectiveness of the assessment also depends on the prompt, rules, provider behavior, and response validation.

## Assessment Response Schema

The server defines a structured response schema requiring four top-level fields:

| Field | Requirement |
|---|---|
| `decision` | Integer `0` or `1`. |
| `reason` | Non-empty string. |
| `evidence` | List of non-empty strings. |
| `recommendations` | List of recommendation objects. |

Each recommendation must contain exactly these fields:

- `priority`
- `action`
- `rationale`

The priority must be `low`, `medium`, or `high`. The action and rationale must be non-empty strings.

The server validates the actual model response through `validate_model_result()`, rather than relying solely on the provider's structured-output features.

### Normalization

After validation, the server strips surrounding whitespace from:

- The assessment reason.
- Each evidence entry.
- Each recommendation's action and rationale.

The normalized result contains only the expected top-level fields and recommendation fields.

The server rejects missing or unexpected fields instead of silently accepting an expanded response structure.

**Decision semantics:**

- `0` means the assessment did not identify a security concern requiring rejection.
- `1` means the assessment identified a concern requiring rejection.

The server returns the decision; downstream KUBAPP code is responsible for enforcing it.

## Provider Dispatch

The `generate_assessment()` function resolves the provider and model through `setup_provider.py`.

It then builds the assessment messages and dispatches the request to the matching provider function.

| Provider | Function | API or endpoint |
|---|---|---|
| Ollama | `_call_ollama()` | Configured Ollama host, `/api/chat`. |
| OpenAI | `_call_openai()` | Configured HTTPS base URL, `/chat/completions`. |
| Google | `_call_google()` | Gemini `generateContent` endpoint. |

An unsupported provider or a failure while resolving the provider/model causes an `AssessmentError`.

The provider-specific functions return a validated assessment result rather than raw provider response data.

## Ollama Integration

`_call_ollama()` obtains the endpoint through `normalize_ollama_host()` and sends a request to `/api/chat`.

The request includes:

- The selected model.
- The system and user messages.
- `stream: false`.
- The server's structured response schema through `format`.
- `temperature: 0`.

The function uses an `httpx.AsyncClient` with the configured timeout and `trust_env=False`.

It logs the model, serialized prompt size, elapsed time, and whether the request succeeded or failed.

The response must contain a dictionary-valued `message` with JSON text in its `content` field. That content is parsed and validated by `extract_json_object()`.

The function does not independently verify that the configured Ollama host is trustworthy or that the model is running locally. Those properties depend on the endpoint configuration and deployment environment.

## OpenAI Integration

`_call_openai()` obtains the API key through `get_setting("OPENAI_API_KEY")`. If the key is absent, it raises `AssessmentError`.

The base URL defaults to:

`https://api.openai.com/v1`

The configured base URL must begin with `https://`.

The function submits a chat-completions request with:

- The selected model.
- The assessment messages.
- `temperature: 0`.
- Strict JSON-schema response formatting.

The request uses bearer-token authentication and an asynchronous HTTP client configured with `trust_env=False`.

The response must contain a non-empty `choices` list. The first choice must provide a dictionary-valued message.

If the message indicates a model refusal, the assessment fails. Otherwise, its content is parsed and validated.

The HTTPS check enforces the URL scheme, but it does not independently establish the trustworthiness of a custom HTTPS host configured as the base URL.

## Google Gemini Integration

`_call_google()` sends the assessment to Google's Gemini `generateContent` endpoint.

The API key is obtained through `get_setting("GOOGLE_API_KEY")`. A missing key causes an assessment failure.

The model name has a leading `models/` prefix removed, if present, and must match the configured regular expression before being inserted into the URL.

The request contains:

- A system instruction derived from the system prompt.
- The serialized assessment rules and untrusted artifact context as user content.
- `temperature: 0`.
- JSON response formatting.
- A response schema describing the expected assessment structure.

The API key is sent in the `x-goog-api-key` header.

### Response Handling

The function records diagnostic information including:

- Selected model.
- Timeout configuration.
- Prompt and payload sizes.
- HTTP status.
- Elapsed time.
- Response content type and byte length.
- The response's `x-request-id` header, when available.

For HTTP errors, it logs a truncated response body and raises `AssessmentError`.

For successful HTTP responses, it parses the JSON and requires at least one candidate. It rejects a response whose first candidate has `finishReason == "SAFETY"`.

It then requires exactly one text part in the candidate content and validates that text as the assessment JSON.

The diagnostic logs include truncated error response bodies. Operators should consider whether those bodies could contain sensitive information before forwarding logs to broader systems.

## HTTP Timeouts and Error Handling

The server uses:

```python
httpx.Timeout(REQUEST_TIMEOUT)
```

with `REQUEST_TIMEOUT` set to 600 seconds.

This configures the HTTP client's timeout behavior. It should not be interpreted as an independent hard deadline covering every operation performed by the server, including provider resolution, prompt loading, and response processing.

The server handles errors at two levels:

1. Provider-specific functions detect and report failures in their own request or response handling.
2. `generate_assessment()` translates provider failures into `AssessmentError` messages.

HTTP status errors are converted into an error containing the provider name and status code. Other HTTP and value errors are converted into provider-request failures. Unexpected exceptions are also wrapped in a general provider-assessment error.

The MCP tool returns a structured result only when the assessment completes successfully and passes validation.

## Integration with the AI Client

The server works with `ai/client.py`, which starts `server.py` as a subprocess using MCP stdio transport.

The expected flow is:

1. The client validates the request envelope.
2. The client launches the server process.
3. The MCP session is initialized.
4. The client discovers `assess_artifact`.
5. The client invokes the tool with the request.
6. The server validates the request and its size.
7. The server loads the prompt and constructs assessment messages.
8. The selected provider generates a response.
9. The server validates and normalizes the response.
10. The client parses and validates the returned tool result.
11. `ai_analysis.py` adds ruleset metadata and returns the normalized assessment result.
12. `platform_decision.py` persists the report and enforces the decision.

This separates provider communication from KUBAPP's downstream decision and execution workflow.

## Security and Reliability Considerations

### 1. Submitted artifacts are not executed by this server

The server serializes the supplied context into assessment messages. It does not invoke the submitted command or script. Actual execution remains the responsibility of other CI components.

### 2. Model output is treated as untrusted until validated

The server checks the response fields, allowed decision values, recommendation priorities, and required string content before returning a result.

These checks protect the expected response contract. They do not prove that the model's conclusion is correct.

### 3. Provider response schemas are not identical

Ollama and OpenAI receive the shared `RESPONSE_SCHEMA`. Google receives a separately constructed response schema.

The Google schema does not declare every restriction present in the shared schema, such as the decision enum and `additionalProperties: false`. The server's own `validate_model_result()` remains the common validation layer for all three providers.

### 4. Network behavior depends on provider configuration

The provider calls use `httpx` with `trust_env=False`, so the client does not automatically use HTTPX's environment-derived proxy configuration. This does not disable network access; the provider requests still require connectivity to the configured endpoint.

### 5. Diagnostic logging requires care

The server logs request metadata and, for Google HTTP errors, up to 4,000 characters of the response body. Although the API-key header is not explicitly printed, error bodies and other diagnostic data should still be handled according to KUBAPP's logging and data-handling requirements.

### 6. The server does not enforce the final CI decision

It returns a validated `decision` value. Rejection handling, report persistence, and preventing the assessed artifact from proceeding are responsibilities of downstream components and their callers.

## Scope and Limitations

`ai/server.py` is responsible for **MCP tool exposure, request validation, prompt construction, provider dispatch, HTTP communication, and assessment-response validation**.

It does not:

- Execute submitted artifacts.
- Independently verify the factual correctness of a model assessment.
- Persist the final assessment report.
- Commit reports to Git.
- Enforce the final decision against the assessed artifact.
- Provide command-execution isolation or sandboxing.
- Guarantee that provider connectivity is restricted to a particular network destination.

It is the provider-facing assessment service within KUBAPP's broader AI-assisted CI workflow.
