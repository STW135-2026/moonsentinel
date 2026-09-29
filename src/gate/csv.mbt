///|
priv struct CsvCell {
  value : String
  quoted : Bool
}

///|
fn csv_decode_field(field : Array[Byte]) -> Result[String, GateError] {
  let bytes = Bytes::from_array(field)
  Ok(
    @utf8.decode(bytes.exact_view(), ignore_bom=false) catch {
      _ => return Err(InvalidInput("CSV contains invalid UTF-8"))
    },
  )
}

///|
fn csv_finish_field(
  field : Array[Byte],
  row : Array[CsvCell],
  quoted : Bool,
) -> Result[Unit, GateError] {
  let value = match csv_decode_field(field) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  row.push({ value, quoted, })
  Ok(())
}

///|
/// Parse comma-separated records, including quoted commas, doubled quotes,
/// LF/CRLF records, and line breaks inside quoted fields.
fn csv_parse(input : String) -> Result[Array[Array[CsvCell]], GateError] {
  let bytes = @utf8.encode(input)
  let mut index = 0
  // Ignore a UTF-8 BOM if one is present at the start of a file.
  if bytes.length() >= 3 &&
    bytes[0].to_int() == 239 &&
    bytes[1].to_int() == 187 &&
    bytes[2].to_int() == 191 {
    index = 3
  }

  let records : Array[Array[CsvCell]] = []
  let mut row : Array[CsvCell] = []
  let mut field : Array[Byte] = []
  let mut in_quotes = false
  let mut after_quote = false
  let mut field_quoted = false
  while index < bytes.length() {
    let current = bytes[index].to_int()
    if in_quotes {
      if current == 34 {
        if index + 1 < bytes.length() && bytes[index + 1].to_int() == 34 {
          field.push(bytes[index])
          index += 2
        } else {
          in_quotes = false
          after_quote = true
          index += 1
        }
      } else {
        field.push(bytes[index])
        index += 1
      }
    } else if after_quote {
      if current == 44 {
        match csv_finish_field(field, row, field_quoted) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        field = []
        field_quoted = false
        after_quote = false
        index += 1
      } else if current == 10 ||
        (
          current == 13 &&
          index + 1 < bytes.length() &&
          bytes[index + 1].to_int() == 10
        ) {
        match csv_finish_field(field, row, field_quoted) {
          Ok(_) => ()
          Err(error) => return Err(error)
        }
        field = []
        field_quoted = false
        records.push(row)
        row = []
        after_quote = false
        if current == 13 {
          index += 2
        } else {
          index += 1
        }
      } else {
        return Err(
          InvalidInput("unexpected character after a quoted CSV field"),
        )
      }
    } else if current == 34 {
      if field.length() != 0 {
        return Err(InvalidInput("quote inside an unquoted CSV field"))
      }
      in_quotes = true
      field_quoted = true
      index += 1
    } else if current == 44 {
      match csv_finish_field(field, row, field_quoted) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      field = []
      field_quoted = false
      index += 1
    } else if current == 10 ||
      (
        current == 13 &&
        index + 1 < bytes.length() &&
        bytes[index + 1].to_int() == 10
      ) {
      match csv_finish_field(field, row, field_quoted) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
      field = []
      field_quoted = false
      records.push(row)
      row = []
      if current == 13 {
        index += 2
      } else {
        index += 1
      }
    } else {
      field.push(bytes[index])
      index += 1
    }
  }

  if in_quotes {
    return Err(InvalidInput("unterminated quoted CSV field"))
  }
  if row.length() > 0 || field.length() > 0 || after_quote {
    match csv_finish_field(field, row, field_quoted) {
      Ok(_) => ()
      Err(error) => return Err(error)
    }
    records.push(row)
  }
  Ok(records)
}

///|
/// Convert a CSV document with a header row to an Arrow batch. Values remain
/// UTF-8 strings; unquoted empty cells are null and quoted empty cells are text.
pub fn csv_to_batch(input : String) -> Result[@arrow.RecordBatch, GateError] {
  let records = match csv_parse(input) {
    Ok(records) => records
    Err(error) => return Err(error)
  }
  if records.is_empty() {
    return Err(InvalidInput("CSV must contain a header row"))
  }
  let headers = records[0].map(cell => cell.value)
  if headers.is_empty() {
    return Err(InvalidInput("CSV must contain at least one column"))
  }
  let seen_headers : Array[String] = []
  for header in headers {
    if header.trim() == "" {
      return Err(InvalidInput("CSV column names must not be empty"))
    }
    if seen_headers.contains(header) {
      return Err(InvalidInput("CSV column names must be unique: " + header))
    }
    seen_headers.push(header)
  }
  for row_index in 1..<records.length() {
    if records[row_index].length() != headers.length() {
      return Err(
        InvalidInput(
          "CSV row has a different number of columns: " +
          (row_index + 1).to_string(),
        ),
      )
    }
  }

  let fields : Array[@arrow.Field] = headers.map(header => {
    @arrow.Field::new(header, @arrow.Utf8)
  })
  let columns : Array[@arrow.Column] = []
  for column_index in 0..<headers.length() {
    let values : Array[String?] = []
    for row_index in 1..<records.length() {
      let cell = records[row_index][column_index]
      values.push(
        if cell.value == "" && !cell.quoted {
          None
        } else {
          Some(cell.value)
        },
      )
    }
    columns.push(@arrow.Strings(values))
  }
  Ok(@arrow.RecordBatch::new(@arrow.Schema::new(fields), columns)) catch {
    _ => Err(InvalidBatch)
  }
}

///|
fn csv_escape_field(value : String) -> Result[String, GateError] {
  let bytes = @utf8.encode(value)
  let mut requires_quotes = value == ""
  for byte in bytes {
    let byte_value = byte.to_int()
    if byte_value == 34 ||
      byte_value == 44 ||
      byte_value == 10 ||
      byte_value == 13 {
      requires_quotes = true
    }
  }
  if !requires_quotes {
    return Ok(value)
  }
  let escaped : Array[Byte] = []
  escaped.push(Byte(34))
  for byte in bytes {
    if byte.to_int() == 34 {
      escaped.push(byte)
    }
    escaped.push(byte)
  }
  escaped.push(Byte(34))
  csv_decode_field(escaped)
}

///|
fn csv_column_value(
  column : @arrow.Column,
  row : Int,
) -> Result[String?, GateError] {
  match column {
    @arrow.Nulls(_) => Ok(None)
    @arrow.Booleans(values) =>
      match values[row] {
        None => Ok(None)
        Some(true) => Ok(Some("true"))
        Some(false) => Ok(Some("false"))
      }
    @arrow.Int32s(values) =>
      match values[row] {
        None => Ok(None)
        Some(value) => Ok(Some(value.to_string()))
      }
    @arrow.Int64s(values) =>
      match values[row] {
        None => Ok(None)
        Some(value) => Ok(Some(value.to_string()))
      }
    @arrow.Float64s(values) =>
      match values[row] {
        None => Ok(None)
        Some(value) => Ok(Some(Json::number(value).stringify()))
      }
    @arrow.Strings(values) =>
      match values[row] {
        None => Ok(None)
        Some(value) => Ok(Some(value))
      }
    @arrow.Binaries(_) =>
      Err(InvalidInput("binary columns cannot be written as CSV"))
  }
}

///|
/// Serialize an Arrow batch as CSV with a header row.
pub fn batch_to_csv(batch : @arrow.RecordBatch) -> Result[String, GateError] {
  match validate_batch(batch) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if batch.schema.fields.is_empty() {
    return Err(InvalidInput("CSV requires at least one column"))
  }
  let output : Array[String] = []
  let headers : Array[String] = []
  for field in batch.schema.fields {
    if field.name.trim() == "" {
      return Err(InvalidInput("CSV column names must not be empty"))
    }
    let encoded = match csv_escape_field(field.name) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    headers.push(encoded)
  }
  output.push(headers.join(","))
  for row in 0..<batch.num_rows {
    let values : Array[String] = []
    for column in batch.columns {
      let value = match csv_column_value(column, row) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      let encoded = match value {
        None => ""
        Some(value) =>
          match csv_escape_field(value) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
      }
      values.push(encoded)
    }
    output.push(values.join(","))
  }
  Ok(output.join("\n"))
}
