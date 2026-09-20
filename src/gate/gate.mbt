///|
/// Errors raised when a privacy policy, release request, or Arrow batch is
/// invalid. Runtime denials are returned as findings inside a ReleaseBundle.
pub(all) enum GateError {
  InvalidPolicy(String)
  InvalidRequest(String)
  InvalidBatch
} derive(Eq, Debug)

///|
/// Trust boundary of the system that will receive the released data.
pub(all) enum Recipient {
  Internal
  Partner
  Public
} derive(Eq, Debug)

///|
/// Privacy classification used to validate release treatments.
pub(all) enum DataClass {
  PublicData
  QuasiIdentifier
  Sensitive
  DirectIdentifier
} derive(Eq, Debug)

///|
/// Output treatment for one input column. Columns absent from the policy are
/// denied by default and never appear in the released RecordBatch.
pub(all) enum Treatment {
  Keep
  ReplaceUtf8(String)
  Drop
} derive(Eq, Debug)

///|
/// Classification and output treatment for one input column.
pub(all) struct ColumnPolicy {
  column : String
  classification : DataClass
  treatment : Treatment
} derive(Eq, Debug)

///|
/// Per-row consent requirement for the requested release purpose.
pub(all) struct ConsentRequirement {
  column : String
  granted_values : Array[String]
} derive(Eq, Debug)

///|
/// One release attempt. Request identifiers are copied into findings and the
/// release manifest to make the decision traceable.
pub(all) struct ReleaseRequest {
  request_id : String
  purpose : String
  recipient : Recipient
} derive(Eq, Debug)

///|
/// Stable machine-readable denial reasons.
pub(all) enum FindingCode {
  PurposeNotAllowed
  RecipientNotAllowed
  MissingColumn
  TypeMismatch
  ConsentMissing
  ConsentDenied
  KAnonymityViolation
} derive(Eq, Debug)

///|
/// One privacy denial. `row=None` denotes a release-wide denial.
pub(all) struct Finding {
  request_id : String
  code : FindingCode
  row : Int?
  column : String?
  message : String
} derive(Eq, Debug)

///|
/// A purpose-bound privacy release policy.
pub struct PrivacyPolicy {
  name : String
  allowed_purposes : Array[String]
  allowed_recipients : Array[Recipient]
  consent : ConsentRequirement
  columns : Array[ColumnPolicy]
  minimum_group_size : Int
  max_findings : Int
}

///|
/// Auditable result of one release attempt.
pub struct PrivacyReport {
  policy_name : String
  request_value : ReleaseRequest
  source_rows : Int
  denial_count_value : Int
  findings_value : Array[Finding]
  truncated_value : Bool
  approved_indices : Array[Int]
  quarantined_indices : Array[Int]
  released_columns_value : Array[String]
  minimum_group_size_value : Int
}

///|
/// Fail-closed outputs of a privacy release attempt.
pub struct ReleaseBundle {
  report_value : PrivacyReport
  approved_value : @arrow.RecordBatch
  quarantine_value : @arrow.RecordBatch
  findings_value : @arrow.RecordBatch
  manifest_value : @arrow.RecordBatch
}

///|
priv struct ReleaseState {
  findings : Array[Finding]
  counts : Array[Int]
  rejected : Array[Bool]
  dataset_denied : Array[Bool]
  max_findings : Int
  request_id : String
}

///|
fn contains_string(values : Array[String], target : String) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn contains_recipient(values : Array[Recipient], target : Recipient) -> Bool {
  for value in values {
    if value == target {
      return true
    }
  }
  false
}

///|
fn recipient_text(recipient : Recipient) -> String {
  match recipient {
    Internal => "internal"
    Partner => "partner"
    Public => "public"
  }
}

///|
fn finding_code_text(code : FindingCode) -> String {
  match code {
    PurposeNotAllowed => "purpose_not_allowed"
    RecipientNotAllowed => "recipient_not_allowed"
    MissingColumn => "missing_column"
    TypeMismatch => "type_mismatch"
    ConsentMissing => "consent_missing"
    ConsentDenied => "consent_denied"
    KAnonymityViolation => "k_anonymity_violation"
  }
}

///|
fn data_type_name(data_type : @arrow.DataType) -> String {
  match data_type {
    @arrow.Null => "null"
    @arrow.Boolean => "bool"
    @arrow.Int32 => "int32"
    @arrow.Int64 => "int64"
    @arrow.Float64 => "float64"
    @arrow.Utf8 => "utf8"
    @arrow.Binary => "binary"
  }
}

///|
fn copy_column_policy(policy : ColumnPolicy) -> ColumnPolicy {
  let treatment = match policy.treatment {
    Keep => Keep
    ReplaceUtf8(value) => ReplaceUtf8(value)
    Drop => Drop
  }
  { column: policy.column, classification: policy.classification, treatment, }
}

///|
fn validate_unique_strings(label : String, values : Array[String]) -> String? {
  if values.is_empty() {
    return Some(label + " must not be empty")
  }
  for index in 0..<values.length() {
    if values[index] == "" {
      return Some(label + " must not contain an empty value")
    }
    for previous in 0..<index {
      if values[index] == values[previous] {
        return Some(label + " contains a duplicate value: " + values[index])
      }
    }
  }
  None
}

///|
fn validate_policy_columns(columns : Array[ColumnPolicy]) -> String? {
  if columns.is_empty() {
    return Some("column policy must not be empty")
  }
  let mut released = 0
  let mut quasi_identifiers = 0
  for index in 0..<columns.length() {
    let policy = columns[index]
    if policy.column == "" {
      return Some("column name must not be empty")
    }
    for previous in 0..<index {
      if policy.column == columns[previous].column {
        return Some("duplicate column policy: " + policy.column)
      }
    }
    match policy.treatment {
      Keep => released += 1
      ReplaceUtf8(replacement) => {
        if replacement == "" {
          return Some("replacement must not be empty: " + policy.column)
        }
        released += 1
      }
      Drop => ()
    }
    match policy.classification {
      DirectIdentifier | Sensitive =>
        if policy.treatment is Keep {
          return Some(
            "direct or sensitive column must be masked or dropped: " +
            policy.column,
          )
        }
      QuasiIdentifier => {
        if !(policy.treatment is Keep) {
          return Some(
            "quasi-identifier must be kept for k-anonymity verification: " +
            policy.column,
          )
        }
        quasi_identifiers += 1
      }
      PublicData => ()
    }
  }
  if released == 0 {
    return Some("policy must release at least one column")
  }
  if quasi_identifiers == 0 {
    return Some("policy must declare at least one quasi-identifier")
  }
  None
}

///|
pub fn PrivacyPolicy::new(
  name : String,
  allowed_purposes : Array[String],
  allowed_recipients : Array[Recipient],
  consent : ConsentRequirement,
  columns : Array[ColumnPolicy],
  minimum_group_size? : Int = 2,
  max_findings? : Int = 100,
) -> Result[PrivacyPolicy, GateError] {
  if name == "" {
    return Err(InvalidPolicy("policy name must not be empty"))
  }
  match validate_unique_strings("allowed purposes", allowed_purposes) {
    Some(message) => return Err(InvalidPolicy(message))
    None => ()
  }
  if allowed_recipients.is_empty() {
    return Err(InvalidPolicy("allowed recipients must not be empty"))
  }
  for index in 0..<allowed_recipients.length() {
    for previous in 0..<index {
      if allowed_recipients[index] == allowed_recipients[previous] {
        return Err(InvalidPolicy("allowed recipients contain duplicates"))
      }
    }
  }
  if consent.column == "" {
    return Err(InvalidPolicy("consent column must not be empty"))
  }
  match
    validate_unique_strings("consent granted values", consent.granted_values) {
    Some(message) => return Err(InvalidPolicy(message))
    None => ()
  }
  match validate_policy_columns(columns) {
    Some(message) => return Err(InvalidPolicy(message))
    None => ()
  }
  if minimum_group_size < 2 {
    return Err(InvalidPolicy("minimum_group_size must be at least 2"))
  }
  if max_findings < 1 {
    return Err(InvalidPolicy("max_findings must be positive"))
  }
  Ok({
    name,
    allowed_purposes: allowed_purposes.copy(),
    allowed_recipients: allowed_recipients.copy(),
    consent: {
      column: consent.column,
      granted_values: consent.granted_values.copy(),
    },
    columns: columns.map(column => copy_column_policy(column)),
    minimum_group_size,
    max_findings,
  })
}

///|
pub fn PrivacyPolicy::name(self : PrivacyPolicy) -> String {
  self.name
}

///|
pub fn PrivacyPolicy::minimum_group_size(self : PrivacyPolicy) -> Int {
  self.minimum_group_size
}

///|
pub fn ReleaseRequest::new(
  request_id : String,
  purpose : String,
  recipient : Recipient,
) -> Result[ReleaseRequest, GateError] {
  if request_id == "" {
    return Err(InvalidRequest("request id must not be empty"))
  }
  if purpose == "" {
    return Err(InvalidRequest("purpose must not be empty"))
  }
  Ok({ request_id, purpose, recipient, })
}

///|
fn field_index(schema : @arrow.Schema, name : String) -> Int? {
  for index in 0..<schema.fields.length() {
    if schema.fields[index].name == name {
      return Some(index)
    }
  }
  None
}

///|
fn record_finding(state : ReleaseState, finding : Finding) -> Unit {
  state.counts[0] = state.counts[0] + 1
  match finding.row {
    Some(row) => state.rejected[row] = true
    None => {
      state.dataset_denied[0] = true
      for row in 0..<state.rejected.length() {
        state.rejected[row] = true
      }
    }
  }
  if state.findings.length() < state.max_findings {
    state.findings.push(finding)
  }
}

///|
fn dataset_finding(
  state : ReleaseState,
  code : FindingCode,
  column : String?,
  message : String,
) -> Unit {
  record_finding(state, {
    request_id: state.request_id,
    code,
    row: None,
    column,
    message,
  })
}

///|
fn row_finding(
  state : ReleaseState,
  code : FindingCode,
  row : Int,
  column : String?,
  message : String,
) -> Unit {
  record_finding(state, {
    request_id: state.request_id,
    code,
    row: Some(row),
    column,
    message,
  })
}

///|
fn validate_batch(batch : @arrow.RecordBatch) -> Result[Unit, GateError] {
  try {
    batch.validate()
    Ok(())
  } catch {
    _ => Err(InvalidBatch)
  }
}

///|
fn validated_batch(
  schema : @arrow.Schema,
  columns : Array[@arrow.Column],
) -> Result[@arrow.RecordBatch, GateError] {
  Ok(@arrow.RecordBatch::new(schema, columns)) catch {
    _ => Err(InvalidBatch)
  }
}

///|
fn take_column(column : @arrow.Column, indices : Array[Int]) -> @arrow.Column {
  match column {
    @arrow.Nulls(_) => @arrow.Nulls(indices.length())
    @arrow.Booleans(values) =>
      @arrow.Booleans(indices.map(index => values[index]))
    @arrow.Int32s(values) => @arrow.Int32s(indices.map(index => values[index]))
    @arrow.Int64s(values) => @arrow.Int64s(indices.map(index => values[index]))
    @arrow.Float64s(values) =>
      @arrow.Float64s(indices.map(index => values[index]))
    @arrow.Strings(values) =>
      @arrow.Strings(indices.map(index => values[index]))
    @arrow.Binaries(values) =>
      @arrow.Binaries(indices.map(index => values[index]))
  }
}

///|
fn take_batch(
  batch : @arrow.RecordBatch,
  indices : Array[Int],
) -> Result[@arrow.RecordBatch, GateError] {
  validated_batch(
    batch.schema,
    batch.columns.map(column => take_column(column, indices)),
  )
}

///|
fn consent_is_granted(value : String, granted_values : Array[String]) -> Bool {
  contains_string(granted_values, value)
}

///|
fn inspect_consent(
  policy : PrivacyPolicy,
  batch : @arrow.RecordBatch,
  state : ReleaseState,
) -> Unit {
  guard field_index(batch.schema, policy.consent.column) is Some(index) else {
    dataset_finding(
      state,
      MissingColumn,
      Some(policy.consent.column),
      "consent column is missing",
    )
    return
  }
  match batch.columns[index] {
    @arrow.Strings(values) =>
      for row in 0..<values.length() {
        match values[row] {
          None =>
            row_finding(
              state,
              ConsentMissing,
              row,
              Some(policy.consent.column),
              "release consent is missing",
            )
          Some(value) if !consent_is_granted(
              value,
              policy.consent.granted_values,
            ) =>
            row_finding(
              state,
              ConsentDenied,
              row,
              Some(policy.consent.column),
              "release consent does not cover the requested purpose",
            )
          _ => ()
        }
      }
    column =>
      dataset_finding(
        state,
        TypeMismatch,
        Some(policy.consent.column),
        "consent column must be utf8, found " +
        data_type_name(column.data_type()),
      )
  }
}

///|
fn quasi_type_supported(column : @arrow.Column) -> Bool {
  match column {
    @arrow.Booleans(_)
    | @arrow.Int32s(_)
    | @arrow.Int64s(_)
    | @arrow.Strings(_) => true
    _ => false
  }
}

///|
fn inspect_policy_columns(
  policy : PrivacyPolicy,
  batch : @arrow.RecordBatch,
  state : ReleaseState,
) -> Unit {
  for column_policy in policy.columns {
    guard field_index(batch.schema, column_policy.column) is Some(index) else {
      dataset_finding(
        state,
        MissingColumn,
        Some(column_policy.column),
        "policy column is missing",
      )
      continue
    }
    match column_policy.treatment {
      ReplaceUtf8(_) if !(batch.columns[index] is @arrow.Strings(_)) =>
        dataset_finding(
          state,
          TypeMismatch,
          Some(column_policy.column),
          "masked column must be utf8",
        )
      _ => ()
    }
    if column_policy.classification is QuasiIdentifier &&
      !quasi_type_supported(batch.columns[index]) {
      dataset_finding(
        state,
        TypeMismatch,
        Some(column_policy.column),
        "quasi-identifier must be bool, int32, int64, or utf8",
      )
    }
  }
}

///|
fn optional_string_key(value : String?) -> String {
  match value {
    None => "n"
    Some(text) => "s" + text.length().to_string() + ":" + text
  }
}

///|
fn optional_int_key(value : Int?) -> String {
  match value {
    None => "n"
    Some(number) => "i:" + number.to_string()
  }
}

///|
fn optional_int64_key(value : Int64?) -> String {
  match value {
    None => "n"
    Some(number) => "l:" + number.to_string()
  }
}

///|
fn optional_bool_key(value : Bool?) -> String {
  match value {
    None => "n"
    Some(true) => "b:1"
    Some(false) => "b:0"
  }
}

///|
fn quasi_value_key(column : @arrow.Column, row : Int) -> String {
  match column {
    @arrow.Booleans(values) => optional_bool_key(values[row])
    @arrow.Int32s(values) => optional_int_key(values[row])
    @arrow.Int64s(values) => optional_int64_key(values[row])
    @arrow.Strings(values) => optional_string_key(values[row])
    _ => "unsupported"
  }
}

///|
fn quasi_indices(
  policy : PrivacyPolicy,
  batch : @arrow.RecordBatch,
) -> Array[Int] {
  let result : Array[Int] = []
  for column_policy in policy.columns {
    if column_policy.classification is QuasiIdentifier {
      match field_index(batch.schema, column_policy.column) {
        Some(index) => result.push(index)
        None => ()
      }
    }
  }
  result
}

///|
fn quasi_names(policy : PrivacyPolicy) -> Array[String] {
  let result : Array[String] = []
  for column_policy in policy.columns {
    if column_policy.classification is QuasiIdentifier {
      result.push(column_policy.column)
    }
  }
  result
}

///|
fn anonymity_key(
  batch : @arrow.RecordBatch,
  indices : Array[Int],
  row : Int,
) -> String {
  indices.map(index => quasi_value_key(batch.columns[index], row)).join("|")
}

///|
fn enforce_k_anonymity(
  policy : PrivacyPolicy,
  batch : @arrow.RecordBatch,
  state : ReleaseState,
) -> Unit {
  if state.dataset_denied[0] {
    return
  }
  let indices = quasi_indices(policy, batch)
  let names = quasi_names(policy).join(",")
  let eligible = state.rejected.map(value => !value)
  let keys = Array::make(batch.num_rows, "")
  for row in 0..<batch.num_rows {
    if eligible[row] {
      keys[row] = anonymity_key(batch, indices, row)
    }
  }
  for row in 0..<batch.num_rows {
    if eligible[row] {
      let mut group_size = 0
      for other in 0..<batch.num_rows {
        if eligible[other] && keys[other] == keys[row] {
          group_size += 1
        }
      }
      if group_size < policy.minimum_group_size {
        row_finding(
          state,
          KAnonymityViolation,
          row,
          Some(names),
          "quasi-identifier group is smaller than the configured minimum",
        )
      }
    }
  }
}

///|
fn released_column_names(policy : PrivacyPolicy) -> Array[String] {
  let names : Array[String] = []
  for column_policy in policy.columns {
    if !(column_policy.treatment is Drop) {
      names.push(column_policy.column)
    }
  }
  names
}

///|
fn empty_batch() -> Result[@arrow.RecordBatch, GateError] {
  validated_batch(@arrow.Schema::new([]), [])
}

///|
fn project_approved(
  policy : PrivacyPolicy,
  batch : @arrow.RecordBatch,
  indices : Array[Int],
) -> Result[@arrow.RecordBatch, GateError] {
  let fields : Array[@arrow.Field] = []
  let columns : Array[@arrow.Column] = []
  for column_policy in policy.columns {
    if !(column_policy.treatment is Drop) {
      guard field_index(batch.schema, column_policy.column) is Some(index) else {
        return Err(InvalidBatch)
      }
      fields.push(batch.schema.fields[index])
      let selected = take_column(batch.columns[index], indices)
      match column_policy.treatment {
        Keep => columns.push(selected)
        ReplaceUtf8(replacement) =>
          match selected {
            @arrow.Strings(values) =>
              columns.push(
                @arrow.Strings(values.map(value => value.map(_ => replacement))),
              )
            _ => return Err(InvalidBatch)
          }
        Drop => ()
      }
    }
  }
  validated_batch(@arrow.Schema::new(fields), columns)
}

///|
fn findings_batch(
  findings : Array[Finding],
) -> Result[@arrow.RecordBatch, GateError] {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("request_id", @arrow.Utf8, nullable=false),
    @arrow.Field::new("code", @arrow.Utf8, nullable=false),
    @arrow.Field::new("row", @arrow.Int32),
    @arrow.Field::new("column", @arrow.Utf8),
    @arrow.Field::new("message", @arrow.Utf8, nullable=false),
  ])
  validated_batch(schema, [
    @arrow.Strings(findings.map(finding => Some(finding.request_id))),
    @arrow.Strings(
      findings.map(finding => Some(finding_code_text(finding.code))),
    ),
    @arrow.Int32s(findings.map(finding => finding.row)),
    @arrow.Strings(findings.map(finding => finding.column)),
    @arrow.Strings(findings.map(finding => Some(finding.message))),
  ])
}

///|
fn manifest_batch(
  report : PrivacyReport,
) -> Result[@arrow.RecordBatch, GateError] {
  let schema = @arrow.Schema::new([
    @arrow.Field::new("request_id", @arrow.Utf8, nullable=false),
    @arrow.Field::new("policy", @arrow.Utf8, nullable=false),
    @arrow.Field::new("purpose", @arrow.Utf8, nullable=false),
    @arrow.Field::new("recipient", @arrow.Utf8, nullable=false),
    @arrow.Field::new("decision", @arrow.Utf8, nullable=false),
    @arrow.Field::new("source_rows", @arrow.Int32, nullable=false),
    @arrow.Field::new("released_rows", @arrow.Int32, nullable=false),
    @arrow.Field::new("quarantined_rows", @arrow.Int32, nullable=false),
    @arrow.Field::new("minimum_group_size", @arrow.Int32, nullable=false),
    @arrow.Field::new("released_columns", @arrow.Utf8, nullable=false),
  ])
  validated_batch(schema, [
    @arrow.Strings([Some(report.request_value.request_id)]),
    @arrow.Strings([Some(report.policy_name)]),
    @arrow.Strings([Some(report.request_value.purpose)]),
    @arrow.Strings([Some(recipient_text(report.request_value.recipient))]),
    @arrow.Strings([Some(report.decision())]),
    @arrow.Int32s([Some(report.source_rows)]),
    @arrow.Int32s([Some(report.approved_indices.length())]),
    @arrow.Int32s([Some(report.quarantined_indices.length())]),
    @arrow.Int32s([Some(report.minimum_group_size_value)]),
    @arrow.Strings([Some(report.released_columns_value.join(","))]),
  ])
}

///|
pub fn PrivacyPolicy::release(
  self : PrivacyPolicy,
  batch : @arrow.RecordBatch,
  request : ReleaseRequest,
) -> Result[ReleaseBundle, GateError] {
  match validate_batch(batch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let state : ReleaseState = {
    findings: [],
    counts: [0],
    rejected: Array::make(batch.num_rows, false),
    dataset_denied: [false],
    max_findings: self.max_findings,
    request_id: request.request_id,
  }
  if !contains_string(self.allowed_purposes, request.purpose) {
    dataset_finding(
      state,
      PurposeNotAllowed,
      None,
      "requested purpose is not allowed by the privacy policy",
    )
  }
  if !contains_recipient(self.allowed_recipients, request.recipient) {
    dataset_finding(
      state,
      RecipientNotAllowed,
      None,
      "recipient trust boundary is not allowed by the privacy policy",
    )
  }
  inspect_consent(self, batch, state)
  inspect_policy_columns(self, batch, state)
  enforce_k_anonymity(self, batch, state)
  let approved_indices : Array[Int] = []
  let quarantined_indices : Array[Int] = []
  for row in 0..<batch.num_rows {
    if state.rejected[row] {
      quarantined_indices.push(row)
    } else {
      approved_indices.push(row)
    }
  }
  let released_columns = released_column_names(self)
  let report : PrivacyReport = {
    policy_name: self.name,
    request_value: request,
    source_rows: batch.num_rows,
    denial_count_value: state.counts[0],
    findings_value: state.findings,
    truncated_value: state.counts[0] > state.findings.length(),
    approved_indices,
    quarantined_indices,
    released_columns_value: released_columns,
    minimum_group_size_value: self.minimum_group_size,
  }
  let approved = if state.dataset_denied[0] {
    match empty_batch() {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  } else {
    match project_approved(self, batch, report.approved_indices) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  let quarantine = match take_batch(batch, report.quarantined_indices) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let findings = match findings_batch(report.findings_value) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let manifest = match manifest_batch(report) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({
    report_value: report,
    approved_value: approved,
    quarantine_value: quarantine,
    findings_value: findings,
    manifest_value: manifest,
  })
}

///|
pub fn PrivacyReport::decision(self : PrivacyReport) -> String {
  if self.denial_count_value == 0 {
    "approved"
  } else if self.approved_indices.is_empty() {
    "denied"
  } else {
    "partial"
  }
}

///|
pub fn PrivacyReport::passed(self : PrivacyReport) -> Bool {
  self.denial_count_value == 0
}

///|
pub fn PrivacyReport::source_row_count(self : PrivacyReport) -> Int {
  self.source_rows
}

///|
pub fn PrivacyReport::approved_row_count(self : PrivacyReport) -> Int {
  self.approved_indices.length()
}

///|
pub fn PrivacyReport::quarantined_row_count(self : PrivacyReport) -> Int {
  self.quarantined_indices.length()
}

///|
pub fn PrivacyReport::denial_count(self : PrivacyReport) -> Int {
  self.denial_count_value
}

///|
pub fn PrivacyReport::findings(self : PrivacyReport) -> Array[Finding] {
  self.findings_value.copy()
}

///|
pub fn PrivacyReport::truncated(self : PrivacyReport) -> Bool {
  self.truncated_value
}

///|
pub fn PrivacyReport::released_columns(self : PrivacyReport) -> Array[String] {
  self.released_columns_value.copy()
}

///|
pub fn PrivacyReport::summary(self : PrivacyReport) -> String {
  self.policy_name +
  "/" +
  self.request_value.request_id +
  ": " +
  self.decision() +
  "; purpose=" +
  self.request_value.purpose +
  "; recipient=" +
  recipient_text(self.request_value.recipient) +
  "; rows=" +
  self.source_rows.to_string() +
  "; released=" +
  self.approved_indices.length().to_string() +
  "; quarantined=" +
  self.quarantined_indices.length().to_string() +
  "; denials=" +
  self.denial_count_value.to_string() +
  "; k=" +
  self.minimum_group_size_value.to_string() +
  "; findings_shown=" +
  self.findings_value.length().to_string() +
  "; truncated=" +
  self.truncated_value.to_string()
}

///|
pub fn ReleaseBundle::report(self : ReleaseBundle) -> PrivacyReport {
  self.report_value
}

///|
pub fn ReleaseBundle::approved(self : ReleaseBundle) -> @arrow.RecordBatch {
  self.approved_value
}

///|
pub fn ReleaseBundle::quarantine(self : ReleaseBundle) -> @arrow.RecordBatch {
  self.quarantine_value
}

///|
pub fn ReleaseBundle::findings(self : ReleaseBundle) -> @arrow.RecordBatch {
  self.findings_value
}

///|
pub fn ReleaseBundle::manifest(self : ReleaseBundle) -> @arrow.RecordBatch {
  self.manifest_value
}
