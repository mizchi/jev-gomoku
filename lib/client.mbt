///|
/// Minimal client for the TypeSafe AI Jev API
/// (http://docs.typesafe.ai, OpenAPI at /openapi.json on the API host).
pub struct Client {
  api_key : String
  base_url : String
}

///|
pub fn Client::new(api_key : String) -> Client {
  { api_key, base_url: "https://api.typesafe.ai", }
}

///|
pub fn Client::with_base_url(api_key : String, base_url : String) -> Client {
  { api_key, base_url, }
}

///|
fn auth_headers(api_key : String) -> Map[@http.CaseInsensitiveString, String] {
  { "authorization": "Bearer \{api_key}", "content-type": "application/json" }
}

///|
/// GET /v1/models — the model names/aliases available to this account.
pub async fn Client::list_models(self : Client) -> Array[Model] {
  let (resp, body) = @http.get(
    "\{self.base_url}/v1/models",
    headers=auth_headers(self.api_key),
  )
  let text = body.text()
  if resp.code != 200 {
    raise ApiError::Http(resp.code, resp.reason, text)
  }
  let json = @json.parse(text) catch {
    _ =>
      raise ApiError::InvalidResponse(
        "models: response is not JSON: \{clamp_text(text)}",
      )
  }
  let m = json_object(json, "models response")
  match m.get("models") {
    Some(Json::Array(items)) => items.map(v => Model::from_json(v))
    Some(other) =>
      raise ApiError::InvalidResponse(
        "models: expected array, got \{other.stringify()}",
      )
    None => raise ApiError::InvalidResponse("models: missing")
  }
}

///|
/// POST /v1/systemone — evaluate all named questions against `state` in a
/// single parallel call. Answers are keyed by question name.
pub async fn Client::system_one(
  self : Client,
  req : SystemOneRequest,
) -> SystemOneResponse {
  req.validate()
  let (resp, body) = @http.post(
    "\{self.base_url}/v1/systemone",
    req.to_json(),
    headers=auth_headers(self.api_key),
  )
  let text = body.text()
  if resp.code != 200 {
    raise ApiError::Http(resp.code, resp.reason, text)
  }
  let json = @json.parse(text) catch {
    _ =>
      raise ApiError::InvalidResponse(
        "systemone: response is not JSON: \{clamp_text(text)}",
      )
  }
  SystemOneResponse::from_json(json)
}

///|
fn clamp_text(s : String) -> String {
  let limit = 400
  if s.length() <= limit {
    s
  } else {
    s[:limit].to_owned() + "…"
  }
}
