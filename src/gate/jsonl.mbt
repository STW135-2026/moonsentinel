///|
priv enum JsonlKind {
  JsonlNull
  JsonlBoolean
  JsonlInt64
  JsonlFloat64
  JsonlUtf8
} derive(Eq)

///|
fn jsonl_kind(value : Json, field : String) -> Result[JsonlKind, GateError] {
  match value {
    Null => Ok(JsonlNull)
    True | False => Ok(JsonlBoolean)
    String(_) => Ok(JsonlUtf8)
    Number(number, ..) => {
      // Json numbers use Double internally. Reject values outside the exact
      // integer range so conversion cannot silently change the input value.
      if number < -9007199254740991.0 || number > 9007199254740991.0 {
        return Err(
          InvalidInput("JSON number exceeds the exact range in field: " + field),
        )
      }
      if number.to_int64().to_double() == number {
        Ok(JsonlInt64)
      } else {
        Ok(JsonlFloat64)
      }
    }
    Array(_) | Object(_) =>
      Err(InvalidInput("nested JSON value is not supported in field: " + field))
  }
}

///|
fn merge_jsonl_kind(
  previous : JsonlKind?,
  incoming : JsonlKind,
  field : String,
) -> Result[JsonlKind, GateError] {
  match previous {
    None => Ok(incoming)
    Some(JsonlNull) => Ok(incoming)
    Some(kind) if incoming is JsonlNull => Ok(kind)
    Some(JsonlInt64) if incoming is JsonlFloat64 => Ok(JsonlFloat64)
    Some(JsonlFloat64) if incoming is JsonlInt64 => Ok(JsonlFloat64)
    Some(kind) if kind == incoming => Ok(kind)
    Some(_) => Err(InvalidInput("mixed JSON scalar types in field: " + field))
  }
}

///|
fn jsonl_arrow_type(kind : JsonlKind) -> @arrow.DataType {
  match kind {
    JsonlNull => @arrow.Null
    JsonlBoolean => @arrow.Boolean
    JsonlInt64 => @arrow.Int64
    JsonlFloat64 => @arrow.Float64
    JsonlUtf8 => @arrow.Utf8
  }
}

///|
/// Convert newline-delimited JSON objects to one Arrow batch. Missing fields
/// and explicit nulls become Arrow nulls. Fields use lexical key order.
pub fn jsonl_to_batch(input : String) -> Result[@arrow.RecordBatch, GateError] {
  let rows : Array[Map[String, Json]] = []
  let mut line_number = 0
  for raw_line in input.split("\n") {
    line_number += 1
    let line = raw_line.trim()
    if line == "" {
      continue
    }
    let parsed = @json.parse(line) catch {
      _ =>
        return Err(
          InvalidInput("invalid JSON at line " + line_number.to_string()),
        )
    }
    match parsed {
      Object(fields) => rows.push(fields)
      _ =>
        return Err(
          InvalidInput(
            "JSONL line must be an object: " + line_number.to_string(),
          ),
        )
    }
  }
  if rows.is_empty() {
    return Err(InvalidInput("JSONL input must contain at least one object"))
  }

  let names : Array[String] = []
  for row in rows {
    for name in row.keys() {
      if name == "" {
        return Err(InvalidInput("JSONL field names must not be empty"))
      }
      if !names.contains(name) {
        names.push(name)
      }
    }
  }
  if names.is_empty() {
    return Err(InvalidInput("JSONL objects must contain at least one field"))
  }
  names.sort_by(fn(a, b) { String::lexical_compare(a, b) })

  let kinds : Array[JsonlKind] = []
  for name in names {
    let mut kind : JsonlKind? = None
    for row in rows {
      let value : Json = match row.get(name) {
        Some(value) => value
        None => null
      }
      let incoming = match jsonl_kind(value, name) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      kind = match merge_jsonl_kind(kind, incoming, name) {
        Ok(value) => Some(value)
        Err(error) => return Err(error)
      }
    }
    kinds.push(kind.unwrap_or(JsonlNull))
  }

  let fields : Array[@arrow.Field] = []
  for index in 0..<names.length() {
    fields.push(@arrow.Field::new(names[index], jsonl_arrow_type(kinds[index])))
  }
  let columns : Array[@arrow.Column] = []
  for index in 0..<names.length() {
    let name = names[index]
    let kind = kinds[index]
    match kind {
      JsonlNull => columns.push(@arrow.Nulls(rows.length()))
      JsonlBoolean =>
        columns.push(
          @arrow.Booleans(
            rows.map(row => {
              match row.get(name) {
                Some(True) => Some(true)
                Some(False) => Some(false)
                _ => None
              }
            }),
          ),
        )
      JsonlInt64 =>
        columns.push(
          @arrow.Int64s(
            rows.map(row => {
              match row.get(name) {
                Some(Number(number, ..)) => Some(number.to_int64())
                _ => None
              }
            }),
          ),
        )
      JsonlFloat64 =>
        columns.push(
          @arrow.Float64s(
            rows.map(row => {
              match row.get(name) {
                Some(Number(number, ..)) => Some(number)
                _ => None
              }
            }),
          ),
        )
      JsonlUtf8 =>
        columns.push(
          @arrow.Strings(
            rows.map(row => {
              match row.get(name) {
                Some(String(value)) => Some(value)
                _ => None
              }
            }),
          ),
        )
    }
  }

  Ok(@arrow.RecordBatch::new(@arrow.Schema::new(fields), columns)) catch {
    _ => Err(InvalidBatch)
  }
}

///|
fn jsonl_column_value(
  column : @arrow.Column,
  row : Int,
  field : String,
) -> Result[String, GateError] {
  match column {
    @arrow.Nulls(_) => Ok("null")
    @arrow.Booleans(values) =>
      match values[row] {
        None => Ok("null")
        Some(true) => Ok("true")
        Some(false) => Ok("false")
      }
    @arrow.Int32s(values) =>
      match values[row] {
        None => Ok("null")
        Some(value) => Ok(value.to_string())
      }
    @arrow.Int64s(values) =>
      match values[row] {
        None => Ok("null")
        Some(value) if value < -9007199254740991 || value > 9007199254740991 =>
          Err(
            InvalidInput(
              "JSON number exceeds the exact range in field: " + field,
            ),
          )
        Some(value) => Ok(value.to_string())
      }
    @arrow.Float64s(values) =>
      match values[row] {
        None => Ok("null")
        Some(value) if value != value ||
          value < -9007199254740991.0 ||
          value > 9007199254740991.0 =>
          Err(
            InvalidInput(
              "JSON number exceeds the exact range in field: " + field,
            ),
          )
        Some(value) => Ok(Json::number(value).stringify())
      }
    @arrow.Strings(values) =>
      match values[row] {
        None => Ok("null")
        Some(value) => Ok(Json::string(value).stringify())
      }
    @arrow.Binaries(_) =>
      Err(InvalidInput("binary columns cannot be written as JSONL"))
  }
}

///|
/// Serialize an Arrow batch as newline-delimited JSON objects.
pub fn batch_to_jsonl(batch : @arrow.RecordBatch) -> Result[String, GateError] {
  match validate_batch(batch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let output : Array[String] = []
  for row in 0..<batch.num_rows {
    let values : Array[String] = []
    for column_index in 0..<batch.columns.length() {
      let name = batch.schema.fields[column_index].name
      let encoded_name = Json::string(name).stringify()
      let encoded_value = match
        jsonl_column_value(batch.columns[column_index], row, name) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      values.push(encoded_name + ":" + encoded_value)
    }
    output.push("{" + values.join(",") + "}")
  }
  Ok(output.join("\n"))
}
