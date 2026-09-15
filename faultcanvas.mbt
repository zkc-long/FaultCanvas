///|
/// Current public API version of the FaultCanvas configuration format.
pub fn config_version() -> Int {
  1
}

///|
/// Validate the basic shape of a request before it enters the rule engine.
pub fn validate_request(
  request : @core.HttpRequest,
  limits : @core.RequestLimits,
) -> Result[Unit, @core.ValidationError] {
  request.validate(limits)
}
