///|
pub(all) enum PathPattern {
  Exact(String)
  Prefix(String)
} derive(Debug, Eq)

///|
pub(all) struct FieldPattern {
  name : String
  value : String
} derive(Debug, Eq)

///|
pub fn FieldPattern::new(name : String, value : String) -> FieldPattern {
  { name, value, }
}

///|
/// An empty optional field is a wildcard. Every configured query and header
/// pattern must be present for the request to match.
pub(all) struct RequestPattern {
  verb : String?
  path : PathPattern?
  query : Array[FieldPattern]
  headers : Array[FieldPattern]
  body_contains : String?
} derive(Debug, Eq)

///|
pub fn RequestPattern::new(
  verb : String?,
  path : PathPattern?,
  query : Array[FieldPattern],
  headers : Array[FieldPattern],
  body_contains : String?,
) -> RequestPattern {
  {
    verb: verb.map(fn(value) { value.to_upper() }),
    path,
    query,
    headers,
    body_contains,
  }
}

///|
pub(all) enum Mismatch {
  Verb(expected~ : String, actual~ : String)
  Path(expected~ : String, actual~ : String)
  MissingQuery(String)
  QueryValue(name~ : String, expected~ : String, actual~ : String)
  MissingHeader(String)
  HeaderValue(name~ : String, expected~ : String, actual~ : String)
  BodySubstring(String)
} derive(Debug, Eq)

///|
pub(all) struct MatchEvaluation {
  matched : Bool
  specificity : Int
  mismatch : Mismatch?
} derive(Debug, Eq)

///|
fn path_matches(pattern : PathPattern, actual : String) -> Bool {
  match pattern {
    Exact(expected) => actual == expected
    Prefix(expected) => actual.has_prefix(expected)
  }
}

///|
fn path_description(pattern : PathPattern) -> String {
  match pattern {
    Exact(expected) => expected
    Prefix(expected) => expected + "*"
  }
}

///|
pub fn RequestPattern::evaluate(
  self : RequestPattern,
  request : @core.HttpRequest,
) -> MatchEvaluation {
  let mut specificity = 0
  match self.verb {
    Some(expected) => {
      specificity = specificity + 1
      if request.verb != expected {
        return {
          matched: false,
          specificity,
          mismatch: Some(Verb(expected~, actual=request.verb)),
        }
      }
    }
    None => ()
  }
  match self.path {
    Some(pattern) => {
      specificity = specificity + 1
      if !path_matches(pattern, request.path) {
        return {
          matched: false,
          specificity,
          mismatch: Some(
            Path(expected=path_description(pattern), actual=request.path),
          ),
        }
      }
    }
    None => ()
  }
  for wanted in self.query {
    specificity = specificity + 1
    match request.query_first(wanted.name) {
      None =>
        return {
          matched: false,
          specificity,
          mismatch: Some(MissingQuery(wanted.name)),
        }
      Some(actual) =>
        if actual != wanted.value {
          return {
            matched: false,
            specificity,
            mismatch: Some(
              QueryValue(name=wanted.name, expected=wanted.value, actual~),
            ),
          }
        }
    }
  }
  for wanted in self.headers {
    specificity = specificity + 1
    match request.header(wanted.name) {
      None =>
        return {
          matched: false,
          specificity,
          mismatch: Some(MissingHeader(wanted.name)),
        }
      Some(actual) =>
        if actual != wanted.value {
          return {
            matched: false,
            specificity,
            mismatch: Some(
              HeaderValue(name=wanted.name, expected=wanted.value, actual~),
            ),
          }
        }
    }
  }
  match self.body_contains {
    Some(expected) => {
      specificity = specificity + 1
      if !request.body.contains(expected) {
        return {
          matched: false,
          specificity,
          mismatch: Some(BodySubstring(expected)),
        }
      }
    }
    None => ()
  }
  { matched: true, specificity, mismatch: None, }
}

///|
pub(all) struct RuleCandidate {
  id : String
  priority : Int
  pattern : RequestPattern
} derive(Debug, Eq)

///|
pub fn RuleCandidate::new(
  id : String,
  priority : Int,
  pattern : RequestPattern,
) -> RuleCandidate {
  { id, priority, pattern, }
}

///|
/// Select the highest priority matching rule. Specificity breaks priority
/// ties, and declaration order breaks complete ties.
pub fn select_index(
  candidates : Array[RuleCandidate],
  request : @core.HttpRequest,
) -> Int? {
  let mut selected = -1
  let mut selected_priority = -2_147_483_648
  let mut selected_specificity = -1
  for index = 0; index < candidates.length(); index = index + 1 {
    let candidate = candidates[index]
    let evaluation = candidate.pattern.evaluate(request)
    if evaluation.matched &&
      (
        candidate.priority > selected_priority ||
        (
          candidate.priority == selected_priority &&
          evaluation.specificity > selected_specificity
        )
      ) {
      selected = index
      selected_priority = candidate.priority
      selected_specificity = evaluation.specificity
    }
  }
  if selected < 0 {
    None
  } else {
    Some(selected)
  }
}
