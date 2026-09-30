//// Typed HTTP client for the Crystalline API.
////
//// Every function returns `Result(T, ClientError)` for a decoded response
//// body `T`. Transport failures, non-2xx responses and decode failures are
//// all reported through `ClientError`. Request and response bodies are
//// produced and consumed with the `facet/models` codecs, so the CLI and the
//// desktop app share exactly one definition of the wire format.

import facet/config.{type Config}
import facet/models
import gleam/dynamic/decode
import gleam/http
import gleam/http/request
import gleam/http/response
import gleam/httpc
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

/// Alias so callers can refer to the error type through the client module.
pub type ClientError =
  config.ClientError

const api_prefix = "/api/v1"

// ─── Health ─────────────────────────────────────────────────────────────────

/// `GET /health`
pub fn health(config: Config) -> Result(models.HealthStatus, ClientError) {
  use req <- result.try(base_request(config, http.Get, "/health"))
  expect_json(config, req, models.decode_health_status())
}

// ─── Tasks ──────────────────────────────────────────────────────────────────

/// `GET /api/v1/tasks` (or `/api/v1/tasks/ready` when `filters.ready`).
pub fn list_tasks(
  config: Config,
  filters: models.TaskFilters,
) -> Result(List(models.Task), ClientError) {
  let path = case filters.ready {
    True -> api_prefix <> "/tasks/ready"
    False -> api_prefix <> "/tasks"
  }

  use req <- result.try(base_request(config, http.Get, path))
  let req = case filters.ready {
    True -> req
    False -> request.set_query(req, models.task_filters_to_query(filters))
  }
  expect_json(config, req, decode.list(models.decode_task()))
}

/// `GET /api/v1/tasks/:id`
pub fn get_task(
  config: Config,
  id: String,
) -> Result(models.Task, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/tasks/" <> path_segment(id),
  ))
  expect_json(config, req, models.decode_task())
}

/// `POST /api/v1/tasks`
pub fn create_task(
  config: Config,
  body: models.TaskCreate,
) -> Result(models.Task, ClientError) {
  use req <- result.try(base_request(config, http.Post, api_prefix <> "/tasks"))
  req
  |> json_body(models.encode_task_create(body))
  |> expect_json(config, _, models.decode_task())
}

/// `PATCH /api/v1/tasks/:id`
pub fn update_task(
  config: Config,
  id: String,
  patch: models.TaskPatch,
) -> Result(models.Task, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Patch,
    api_prefix <> "/tasks/" <> path_segment(id),
  ))
  req
  |> json_body(models.encode_task_patch(patch))
  |> expect_json(config, _, models.decode_task())
}

/// `DELETE /api/v1/tasks/:id?cascade=...`
pub fn delete_task(
  config: Config,
  id: String,
  cascade: Bool,
) -> Result(Nil, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Delete,
    api_prefix <> "/tasks/" <> path_segment(id),
  ))
  let req =
    request.set_query(req, [
      #("cascade", case cascade {
        True -> "true"
        False -> "false"
      }),
    ])
  expect_empty(config, req)
}

// ─── Task dependencies ─────────────────────────────────────────────────────

/// `POST /api/v1/tasks/:id/dependencies` — makes `task_id` depend on
/// `depends_on`, so `task_id` is blocked while `depends_on` is open.
pub fn add_dependency(
  config: Config,
  task_id: String,
  depends_on: String,
) -> Result(models.Message, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/tasks/" <> path_segment(task_id) <> "/dependencies",
  ))
  req
  |> json_body(
    models.encode_dependency_request(models.DependencyRequest(depends_on:)),
  )
  |> expect_json(config, _, models.decode_message())
}

/// `DELETE /api/v1/tasks/:id/dependencies/:depends_on` — removes the edge.
pub fn remove_dependency(
  config: Config,
  task_id: String,
  depends_on: String,
) -> Result(models.Message, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Delete,
    api_prefix
      <> "/tasks/"
      <> path_segment(task_id)
      <> "/dependencies/"
      <> path_segment(depends_on),
  ))
  expect_json(config, req, models.decode_message())
}

/// `GET /api/v1/tasks/:id/blockers` — tasks that block `id`.
pub fn get_blockers(
  config: Config,
  id: String,
) -> Result(List(models.Task), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/tasks/" <> path_segment(id) <> "/blockers",
  ))
  expect_json(config, req, decode.list(models.decode_task()))
}

// ─── Task sections ──────────────────────────────────────────────────────────

/// `GET /api/v1/tasks/:id/sections` — the structured sections of a task.
/// Crystalline builds without the sections API (crystalline#16) answer 404,
/// which surfaces as `HttpError(404, ...)`.
pub fn list_sections(
  config: Config,
  id: String,
) -> Result(List(models.Section), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/tasks/" <> path_segment(id) <> "/sections",
  ))
  expect_json(config, req, decode.list(models.decode_section()))
}

/// `POST /api/v1/tasks/:id/sections` — append a section to a task.
pub fn create_section(
  config: Config,
  id: String,
  body: models.SectionCreate,
) -> Result(models.Section, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/tasks/" <> path_segment(id) <> "/sections",
  ))
  req
  |> json_body(models.encode_section_create(body))
  |> expect_json(config, _, models.decode_section())
}

// ─── Flow templates ─────────────────────────────────────────────────────────

/// `GET /api/v1/flow-templates`
pub fn list_templates(
  config: Config,
) -> Result(List(models.FlowTemplate), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/flow-templates",
  ))
  expect_json(config, req, decode.list(models.decode_flow_template()))
}

/// `GET /api/v1/flow-templates/:id`
pub fn get_template(
  config: Config,
  id: String,
) -> Result(models.FlowTemplate, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/flow-templates/" <> path_segment(id),
  ))
  expect_json(config, req, models.decode_flow_template())
}

// ─── Flow execution ─────────────────────────────────────────────────────────

/// `GET /api/v1/flows/:instance_id` — current execution state of a flow
/// instance (status, current node, step history, variables).
pub fn get_flow_state(
  config: Config,
  instance_id: String,
) -> Result(models.ExecutionState, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/flows/" <> path_segment(instance_id),
  ))
  expect_json(config, req, models.decode_execution_state())
}

/// `POST /api/v1/tasks/:task_id/flow`
pub fn start_flow(
  config: Config,
  task_id: String,
  template_id: String,
) -> Result(models.FlowInstance, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/tasks/" <> path_segment(task_id) <> "/flow",
  ))
  req
  |> json_body(
    models.encode_start_flow_request(models.StartFlowRequest(template_id:)),
  )
  |> expect_json(config, _, models.decode_flow_instance())
}

/// `POST /api/v1/flows/:instance_id/advance` — returns the engine `Action`.
pub fn advance_flow(
  config: Config,
  instance_id: String,
) -> Result(models.Action, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/flows/" <> path_segment(instance_id) <> "/advance",
  ))
  expect_json(config, req, models.decode_action())
}

/// `POST /api/v1/flows/:instance_id/steps/:step_id/complete`
pub fn complete_step(
  config: Config,
  instance_id: String,
  step_id: String,
  output: String,
) -> Result(models.ExecutionState, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix
      <> "/flows/"
      <> path_segment(instance_id)
      <> "/steps/"
      <> path_segment(step_id)
      <> "/complete",
  ))
  req
  |> json_body(
    models.encode_complete_step_request(models.CompleteStepRequest(output:)),
  )
  |> expect_json(config, _, models.decode_execution_state())
}

/// `POST /api/v1/flows/:instance_id/input`
pub fn provide_input(
  config: Config,
  instance_id: String,
  input_text: String,
) -> Result(models.ExecutionState, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/flows/" <> path_segment(instance_id) <> "/input",
  ))
  req
  |> json_body(
    models.encode_provide_input_request(models.ProvideInputRequest(
      input: input_text,
    )),
  )
  |> expect_json(config, _, models.decode_execution_state())
}

/// `POST /api/v1/flows/:instance_id/reject`
pub fn reject_flow(
  config: Config,
  instance_id: String,
  reason: String,
) -> Result(models.ExecutionState, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/flows/" <> path_segment(instance_id) <> "/reject",
  ))
  req
  |> json_body(
    models.encode_reject_flow_request(models.RejectFlowRequest(reason:)),
  )
  |> expect_json(config, _, models.decode_execution_state())
}

// ─── Executions ─────────────────────────────────────────────────────────────

/// `GET /api/v1/tasks/:task_id/executions` — step execution history.
pub fn execution_history(
  config: Config,
  task_id: String,
) -> Result(List(models.StepExecution), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/tasks/" <> path_segment(task_id) <> "/executions",
  ))
  expect_json(config, req, decode.list(models.decode_step_execution()))
}

/// `GET /api/v1/executions/:id`
pub fn get_execution(
  config: Config,
  id: String,
) -> Result(models.StepExecution, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/executions/" <> path_segment(id),
  ))
  expect_json(config, req, models.decode_step_execution())
}

/// `GET /api/v1/executions/active`
pub fn active_executions(
  config: Config,
) -> Result(List(models.StepExecution), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/executions/active",
  ))
  expect_json(config, req, decode.list(models.decode_step_execution()))
}

/// `GET /api/v1/executions/:id/logs?limit=&before_sequence=`
pub fn get_logs(
  config: Config,
  exec_id: String,
  limit: Option(Int),
  before_sequence: Option(Int),
) -> Result(List(models.SessionLog), ClientError) {
  use req <- result.try(base_request(
    config,
    http.Get,
    api_prefix <> "/executions/" <> path_segment(exec_id) <> "/logs",
  ))
  let params = [
    #("limit", int.to_string(limit |> option_or_default(100))),
    #(
      "before_sequence",
      before_sequence |> option_map_or_default(int.to_string, ""),
    ),
  ]
  let req =
    request.set_query(req, list.filter(params, fn(pair) { pair.1 != "" }))
  expect_json(config, req, decode.list(models.decode_session_log()))
}

/// `POST /api/v1/executions/:id/logs`
pub fn append_log(
  config: Config,
  exec_id: String,
  event: models.AppendLogRequest,
) -> Result(models.SessionLog, ClientError) {
  use req <- result.try(base_request(
    config,
    http.Post,
    api_prefix <> "/executions/" <> path_segment(exec_id) <> "/logs",
  ))
  req
  |> json_body(models.encode_append_log_request(event))
  |> expect_json(config, _, models.decode_session_log())
}

// ─── Request building ───────────────────────────────────────────────────────

/// Build an authenticated request against `config.base_url`.
pub fn base_request(
  config: Config,
  method: http.Method,
  path: String,
) -> Result(request.Request(String), ClientError) {
  case request.to(trim_trailing_slashes(config.base_url) <> path) {
    Error(_) ->
      Error(config.ConfigError("invalid base URL: " <> config.base_url))
    Ok(req) ->
      Ok(
        req
        |> request.set_method(method)
        |> request.set_header("accept", "application/json")
        |> add_auth(config),
      )
  }
}

fn add_auth(
  req: request.Request(String),
  config: Config,
) -> request.Request(String) {
  case config.token {
    Some(token) -> request.set_header(req, "authorization", "Bearer " <> token)
    None -> req
  }
}

fn json_body(
  req: request.Request(String),
  body: json.Json,
) -> request.Request(String) {
  req
  |> request.set_header("content-type", "application/json")
  |> request.set_body(json.to_string(body))
}

fn trim_trailing_slashes(url: String) -> String {
  case string.ends_with(url, "/") {
    True -> string.drop_end(url, 1)
    False -> url
  }
}

fn path_segment(value: String) -> String {
  uri.percent_encode(value)
}

fn option_or_default(option: Option(a), default: a) -> a {
  case option {
    Some(value) -> value
    None -> default
  }
}

fn option_map_or_default(
  option: Option(a),
  mapper: fn(a) -> b,
  default: b,
) -> b {
  case option {
    Some(value) -> mapper(value)
    None -> default
  }
}

// ─── Sending / decoding ─────────────────────────────────────────────────────

pub fn send(
  _config: Config,
  req: request.Request(String),
) -> Result(response.Response(String), ClientError) {
  case httpc.send(req) {
    Ok(resp) -> Ok(resp)
    Error(error) -> Error(config.NetworkError(httpc_error_to_string(error)))
  }
}

fn expect_json(
  config: Config,
  req: request.Request(String),
  decoder: decode.Decoder(t),
) -> Result(t, ClientError) {
  use resp <- result.try(send(config, req))
  case resp.status >= 200 && resp.status < 300 {
    True ->
      case json.parse(resp.body, decoder) {
        Ok(value) -> Ok(value)
        Error(error) -> Error(config.DecodeError(json_error_to_string(error)))
      }
    False -> Error(config.HttpError(resp.status, resp.body))
  }
}

fn expect_empty(
  config: Config,
  req: request.Request(String),
) -> Result(Nil, ClientError) {
  use resp <- result.try(send(config, req))
  case resp.status >= 200 && resp.status < 300 {
    True -> Ok(Nil)
    False -> Error(config.HttpError(resp.status, resp.body))
  }
}

fn httpc_error_to_string(error: httpc.HttpError) -> String {
  case error {
    httpc.InvalidUtf8Response -> "invalid UTF-8 response"
    httpc.FailedToConnect(_, _) -> "failed to connect to the server"
    httpc.ResponseTimeout -> "request timed out"
  }
}

fn json_error_to_string(error: json.DecodeError) -> String {
  case error {
    json.UnexpectedEndOfInput -> "unexpected end of JSON input"
    json.UnexpectedByte(byte) -> "unexpected byte in JSON: " <> byte
    json.UnexpectedSequence(sequence) ->
      "unexpected sequence in JSON: " <> sequence
    json.UnableToDecode(errors) ->
      "unable to decode JSON: " <> string.inspect(errors)
  }
}
