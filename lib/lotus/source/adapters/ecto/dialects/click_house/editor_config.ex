defmodule Lotus.Source.Adapters.Ecto.Dialects.ClickHouse.EditorConfig do
  @moduledoc """
  Editor-side vocabulary for the ClickHouse dialect.

  `config/0` returns the payload the dialect hands back from
  `c:Lotus.Source.Adapters.Ecto.Dialect.editor_config/0`: the
  `sql:clickhouse` language identifier, ClickHouse keywords and types
  including the `Nullable` and `LowCardinality` wrappers, function
  completions with signatures, and the clause names that act as context
  boundaries for completion.

  It carries no `:dialect_spec`, and CodeMirror ships no ClickHouse grammar,
  so the editor tokenizes as generic SQL and draws its completions from the
  lists here rather than from a ClickHouse parser.
  """

  def config do
    %{
      # The `family:dialect` identifier, not a bare family: the editor reads
      # the part after the colon to pick a tokenizer, so "sql" alone would
      # drop every ClickHouse keyword and function declared below.
      language: "sql:clickhouse",
      keywords: ~w(PREWHERE FINAL SAMPLE SETTINGS FORMAT ENGINE
           TTL MATERIALIZED POPULATE MODIFY ATTACH DETACH OPTIMIZE FREEZE
           SYSTEM RELOAD DICTIONARIES DICTIONARY KILL QUERY MUTATION
           TOTALS ROLLUP CUBE DEDUPLICATE CLEANUP
           LIVE WINDOW EXCHANGE RENAME DESCRIBE
           WATCH EVENTS GRANT REVOKE INTERPOLATE),
      types: ~w(UInt8 UInt16 UInt32 UInt64 UInt128 UInt256
           Int8 Int16 Int32 Int64 Int128 Int256
           Float32 Float64
           Decimal Decimal32 Decimal64 Decimal128 Decimal256
           String FixedString
           UUID
           Date Date32 DateTime DateTime64
           Enum8 Enum16
           Array Tuple Map Nested
           Nullable LowCardinality
           SimpleAggregateFunction AggregateFunction
           IPv4 IPv6
           Bool Nothing
           JSON Object
           Point Ring Polygon MultiPolygon
           IntervalYear IntervalMonth IntervalWeek IntervalDay
           IntervalHour IntervalMinute IntervalSecond IntervalNanosecond),
      functions: clickhouse_functions(),
      context_boundaries: ~w(prewhere final sample settings format)
    }
  end

  defp clickhouse_functions do
    aggregate_functions() ++
      array_functions() ++
      date_functions() ++
      string_functions() ++
      type_conversion_functions() ++
      math_functions() ++
      conditional_functions() ++
      hash_functions() ++
      url_functions() ++
      ip_functions() ++
      json_functions() ++
      encoding_functions() ++
      geo_functions() ++
      null_functions() ++
      window_functions() ++
      other_functions()
  end

  defp aggregate_functions do
    [
      %{name: "uniq", detail: "Approx distinct count", args: "(column)"},
      %{name: "uniqExact", detail: "Exact distinct count", args: "(column)"},
      %{name: "uniqCombined", detail: "Approx distinct (HLL)", args: "(column)"},
      %{name: "uniqCombined64", detail: "Approx distinct 64-bit", args: "(column)"},
      %{name: "uniqHLL12", detail: "HyperLogLog distinct", args: "(column)"},
      %{name: "uniqTheta", detail: "Theta sketch distinct", args: "(column)"},
      %{name: "groupArray", detail: "Aggregate into array", args: "(column)"},
      %{
        name: "groupArrayInsertAt",
        detail: "Insert into array at position",
        args: "(value, position)"
      },
      %{name: "groupArrayMovingAvg", detail: "Moving average array", args: "(column)"},
      %{name: "groupArrayMovingSum", detail: "Moving sum array", args: "(column)"},
      %{name: "groupUniqArray", detail: "Unique values array", args: "(column)"},
      %{name: "groupArraySorted", detail: "Sorted aggregate array", args: "(N)(column)"},
      %{name: "groupBitAnd", detail: "Bitwise AND aggregate", args: "(column)"},
      %{name: "groupBitOr", detail: "Bitwise OR aggregate", args: "(column)"},
      %{name: "groupBitXor", detail: "Bitwise XOR aggregate", args: "(column)"},
      %{name: "groupBitmap", detail: "Bitmap aggregate", args: "(column)"},
      %{name: "argMin", detail: "Value at min", args: "(value, key)"},
      %{name: "argMax", detail: "Value at max", args: "(value, key)"},
      %{name: "any", detail: "Any value from group", args: "(column)"},
      %{name: "anyLast", detail: "Last value from group", args: "(column)"},
      %{name: "anyHeavy", detail: "Frequent value", args: "(column)"},
      %{name: "topK", detail: "Top K frequent values", args: "(N)(column)"},
      %{name: "topKWeighted", detail: "Top K weighted", args: "(N)(column, weight)"},
      %{name: "quantile", detail: "Quantile (approx)", args: "(level)(column)"},
      %{name: "quantileExact", detail: "Exact quantile", args: "(level)(column)"},
      %{name: "quantileTDigest", detail: "T-digest quantile", args: "(level)(column)"},
      %{name: "quantileTiming", detail: "Timing quantile", args: "(level)(column)"},
      %{
        name: "quantileDeterministic",
        detail: "Deterministic quantile",
        args: "(level)(column, determinator)"
      },
      %{name: "quantiles", detail: "Multiple quantiles", args: "(level1, level2, ...)(column)"},
      %{name: "median", detail: "Median value", args: "(column)"},
      %{name: "simpleLinearRegression", detail: "Simple linear regression", args: "(y, x)"},
      %{name: "corr", detail: "Correlation", args: "(x, y)"},
      %{name: "covarPop", detail: "Population covariance", args: "(x, y)"},
      %{name: "covarSamp", detail: "Sample covariance", args: "(x, y)"},
      %{name: "varPop", detail: "Population variance", args: "(column)"},
      %{name: "varSamp", detail: "Sample variance", args: "(column)"},
      %{name: "stddevPop", detail: "Population std deviation", args: "(column)"},
      %{name: "stddevSamp", detail: "Sample std deviation", args: "(column)"},
      %{name: "sumMap", detail: "Sum map values", args: "(keys, values)"},
      %{name: "minMap", detail: "Min map values", args: "(keys, values)"},
      %{name: "maxMap", detail: "Max map values", args: "(keys, values)"},
      %{name: "avgWeighted", detail: "Weighted average", args: "(value, weight)"},
      %{name: "deltaSum", detail: "Sum of consecutive diffs", args: "(column)"},
      %{
        name: "deltaSumTimestamp",
        detail: "Delta sum with timestamp",
        args: "(value, timestamp)"
      },
      %{name: "retention", detail: "Retention analysis", args: "(cond1, cond2, ...)"},
      %{
        name: "windowFunnel",
        detail: "Funnel analysis",
        args: "(window)(timestamp, cond1, cond2, ...)"
      },
      %{
        name: "sequenceMatch",
        detail: "Event sequence match",
        args: "('pattern')(timestamp, cond1, cond2, ...)"
      },
      %{
        name: "sequenceCount",
        detail: "Event sequence count",
        args: "('pattern')(timestamp, cond1, cond2, ...)"
      },
      %{name: "histogram", detail: "Histogram", args: "(number_of_bins)(column)"},
      %{name: "entropy", detail: "Shannon entropy", args: "(column)"},
      %{name: "rankCorr", detail: "Rank correlation", args: "(x, y)"},
      %{name: "exponentialMovingAverage", detail: "EMA", args: "(value, timeunit, halflife)"}
    ]
  end

  defp array_functions do
    [
      %{name: "arrayJoin", detail: "Unpack array to rows", args: "(array)"},
      %{name: "empty", detail: "Check if empty", args: "(array)"},
      %{name: "notEmpty", detail: "Check if not empty", args: "(array)"},
      %{name: "length", detail: "Array length", args: "(array)"},
      %{name: "arrayConcat", detail: "Concatenate arrays", args: "(arr1, arr2, ...)"},
      %{name: "arrayElement", detail: "Get element at index", args: "(array, index)"},
      %{name: "has", detail: "Check if contains", args: "(array, element)"},
      %{name: "hasAll", detail: "Check contains all", args: "(set, subset)"},
      %{name: "hasAny", detail: "Check contains any", args: "(array1, array2)"},
      %{name: "indexOf", detail: "Index of element", args: "(array, element)"},
      %{name: "countEqual", detail: "Count equal elements", args: "(array, element)"},
      %{name: "arrayEnumerate", detail: "Enumerate elements", args: "(array)"},
      %{name: "arrayEnumerateUniq", detail: "Enumerate unique", args: "(array)"},
      %{name: "arrayPopBack", detail: "Remove last element", args: "(array)"},
      %{name: "arrayPopFront", detail: "Remove first element", args: "(array)"},
      %{name: "arrayPushBack", detail: "Append element", args: "(array, value)"},
      %{name: "arrayPushFront", detail: "Prepend element", args: "(array, value)"},
      %{name: "arraySlice", detail: "Slice array", args: "(array, offset[, length])"},
      %{name: "arraySort", detail: "Sort array", args: "([func, ]array)"},
      %{name: "arrayReverseSort", detail: "Reverse sort array", args: "([func, ]array)"},
      %{name: "arrayUniq", detail: "Count unique elements", args: "(array)"},
      %{name: "arrayDistinct", detail: "Remove duplicates", args: "(array)"},
      %{name: "arrayIntersect", detail: "Array intersection", args: "(arr1, arr2, ...)"},
      %{name: "arrayReduce", detail: "Apply aggregate to array", args: "('agg', array)"},
      %{name: "arrayReverse", detail: "Reverse array", args: "(array)"},
      %{name: "arrayFlatten", detail: "Flatten nested arrays", args: "(array)"},
      %{name: "arrayCompact", detail: "Remove consecutive duplicates", args: "(array)"},
      %{name: "arrayZip", detail: "Zip arrays", args: "(arr1, arr2, ...)"},
      %{name: "arrayMap", detail: "Map lambda over array", args: "(func, array)"},
      %{name: "arrayFilter", detail: "Filter array", args: "(func, array)"},
      %{name: "arrayFirst", detail: "First matching element", args: "(func, array)"},
      %{name: "arrayFirstIndex", detail: "First matching index", args: "(func, array)"},
      %{name: "arrayExists", detail: "Any element matches", args: "(func, array)"},
      %{name: "arrayAll", detail: "All elements match", args: "(func, array)"},
      %{name: "arraySum", detail: "Sum elements", args: "([func, ]array)"},
      %{name: "arrayAvg", detail: "Average elements", args: "([func, ]array)"},
      %{name: "arrayMin", detail: "Min element", args: "([func, ]array)"},
      %{name: "arrayMax", detail: "Max element", args: "([func, ]array)"},
      %{name: "arrayCount", detail: "Count matching", args: "([func, ]array)"},
      %{name: "arrayCumSum", detail: "Cumulative sum", args: "([func, ]array)"},
      %{name: "arrayDifference", detail: "Consecutive differences", args: "(array)"},
      %{name: "arrayStringConcat", detail: "Join as string", args: "(array[, separator])"}
    ]
  end

  defp date_functions do
    [
      %{name: "toDate", detail: "Convert to Date", args: "(value)"},
      %{name: "toDate32", detail: "Convert to Date32", args: "(value)"},
      %{name: "toDateTime", detail: "Convert to DateTime", args: "(value[, timezone])"},
      %{
        name: "toDateTime64",
        detail: "Convert to DateTime64",
        args: "(value, scale[, timezone])"
      },
      %{name: "now", detail: "Current timestamp", args: "()"},
      %{
        name: "now64",
        detail: "Current timestamp with subseconds",
        args: "([scale[, timezone]])"
      },
      %{name: "today", detail: "Current date", args: "()"},
      %{name: "yesterday", detail: "Yesterday's date", args: "()"},
      %{name: "toYear", detail: "Extract year", args: "(date)"},
      %{name: "toMonth", detail: "Extract month", args: "(date)"},
      %{name: "toDayOfMonth", detail: "Day of month", args: "(date)"},
      %{name: "toDayOfWeek", detail: "Day of week (1=Mon)", args: "(date)"},
      %{name: "toDayOfYear", detail: "Day of year", args: "(date)"},
      %{name: "toHour", detail: "Extract hour", args: "(datetime)"},
      %{name: "toMinute", detail: "Extract minute", args: "(datetime)"},
      %{name: "toSecond", detail: "Extract second", args: "(datetime)"},
      %{name: "toQuarter", detail: "Extract quarter", args: "(date)"},
      %{name: "toMonday", detail: "Round down to Monday", args: "(date)"},
      %{name: "toStartOfYear", detail: "Start of year", args: "(date)"},
      %{name: "toStartOfQuarter", detail: "Start of quarter", args: "(date)"},
      %{name: "toStartOfMonth", detail: "Start of month", args: "(date)"},
      %{name: "toStartOfWeek", detail: "Start of week", args: "(date[, mode])"},
      %{name: "toStartOfDay", detail: "Start of day", args: "(datetime)"},
      %{name: "toStartOfHour", detail: "Start of hour", args: "(datetime)"},
      %{name: "toStartOfMinute", detail: "Start of minute", args: "(datetime)"},
      %{name: "toStartOfFiveMinutes", detail: "Round to 5 min", args: "(datetime)"},
      %{name: "toStartOfTenMinutes", detail: "Round to 10 min", args: "(datetime)"},
      %{name: "toStartOfFifteenMinutes", detail: "Round to 15 min", args: "(datetime)"},
      %{name: "toStartOfInterval", detail: "Start of interval", args: "(date, INTERVAL n unit)"},
      %{
        name: "formatDateTime",
        detail: "Format datetime",
        args: "(datetime, format[, timezone])"
      },
      %{name: "parseDateTimeBestEffort", detail: "Parse datetime flexibly", args: "(string)"},
      %{
        name: "parseDateTimeBestEffortOrNull",
        detail: "Parse datetime or null",
        args: "(string)"
      },
      %{
        name: "parseDateTimeBestEffortOrZero",
        detail: "Parse datetime or zero",
        args: "(string)"
      },
      %{name: "date_diff", detail: "Difference between dates", args: "('unit', start, end)"},
      %{name: "date_add", detail: "Add to date", args: "(unit, amount, date)"},
      %{name: "date_sub", detail: "Subtract from date", args: "(unit, amount, date)"},
      %{name: "date_trunc", detail: "Truncate date", args: "('unit', date)"},
      %{name: "addYears", detail: "Add years", args: "(date, N)"},
      %{name: "addMonths", detail: "Add months", args: "(date, N)"},
      %{name: "addWeeks", detail: "Add weeks", args: "(date, N)"},
      %{name: "addDays", detail: "Add days", args: "(date, N)"},
      %{name: "addHours", detail: "Add hours", args: "(datetime, N)"},
      %{name: "addMinutes", detail: "Add minutes", args: "(datetime, N)"},
      %{name: "addSeconds", detail: "Add seconds", args: "(datetime, N)"},
      %{name: "subtractYears", detail: "Subtract years", args: "(date, N)"},
      %{name: "subtractMonths", detail: "Subtract months", args: "(date, N)"},
      %{name: "subtractDays", detail: "Subtract days", args: "(date, N)"},
      %{name: "subtractHours", detail: "Subtract hours", args: "(datetime, N)"},
      %{name: "subtractMinutes", detail: "Subtract minutes", args: "(datetime, N)"},
      %{name: "subtractSeconds", detail: "Subtract seconds", args: "(datetime, N)"},
      %{name: "toYYYYMM", detail: "Format as YYYYMM", args: "(date)"},
      %{name: "toYYYYMMDD", detail: "Format as YYYYMMDD", args: "(date)"},
      %{name: "toYYYYMMDDhhmmss", detail: "Format as YYYYMMDDhhmmss", args: "(datetime)"},
      %{name: "toUnixTimestamp", detail: "Convert to unix timestamp", args: "(datetime)"},
      %{name: "fromUnixTimestamp", detail: "From unix timestamp", args: "(timestamp)"},
      %{name: "dateName", detail: "Named part of date", args: "('part', date)"},
      %{name: "monthName", detail: "Month name", args: "(date)"},
      %{name: "timeZone", detail: "Server timezone", args: "()"},
      %{name: "toTimeZone", detail: "Convert timezone", args: "(datetime, timezone)"}
    ]
  end

  defp string_functions do
    [
      %{name: "lengthUTF8", detail: "UTF-8 length", args: "(string)"},
      %{name: "lower", detail: "Lowercase", args: "(string)"},
      %{name: "upper", detail: "Uppercase", args: "(string)"},
      %{name: "reverse", detail: "Reverse string", args: "(string)"},
      %{name: "concat", detail: "Concatenate strings", args: "(s1, s2, ...)"},
      %{name: "substring", detail: "Substring", args: "(string, offset[, length])"},
      %{name: "trim", detail: "Trim whitespace", args: "(string)"},
      %{name: "trimLeft", detail: "Trim left", args: "(string)"},
      %{name: "trimRight", detail: "Trim right", args: "(string)"},
      %{name: "leftPad", detail: "Left pad", args: "(string, length[, pad])"},
      %{name: "rightPad", detail: "Right pad", args: "(string, length[, pad])"},
      %{name: "splitByChar", detail: "Split by character", args: "(separator, string)"},
      %{name: "splitByString", detail: "Split by string", args: "(separator, string)"},
      %{name: "splitByRegexp", detail: "Split by regex", args: "(regexp, string)"},
      %{
        name: "replaceOne",
        detail: "Replace first occurrence",
        args: "(string, pattern, replacement)"
      },
      %{
        name: "replaceAll",
        detail: "Replace all occurrences",
        args: "(string, pattern, replacement)"
      },
      %{
        name: "replaceRegexpOne",
        detail: "Regex replace first",
        args: "(string, pattern, replacement)"
      },
      %{
        name: "replaceRegexpAll",
        detail: "Regex replace all",
        args: "(string, pattern, replacement)"
      },
      %{name: "like", detail: "LIKE pattern match", args: "(string, pattern)"},
      %{name: "notLike", detail: "NOT LIKE", args: "(string, pattern)"},
      %{name: "ilike", detail: "Case-insensitive LIKE", args: "(string, pattern)"},
      %{name: "match", detail: "Regex match", args: "(string, pattern)"},
      %{name: "extract", detail: "Regex extract first group", args: "(string, pattern)"},
      %{name: "extractAll", detail: "Regex extract all matches", args: "(string, pattern)"},
      %{
        name: "multiMatchAny",
        detail: "Any of multiple patterns match",
        args: "(string, [patterns])"
      },
      %{name: "position", detail: "Position of substring", args: "(haystack, needle)"},
      %{
        name: "positionCaseInsensitive",
        detail: "Case-insensitive position",
        args: "(haystack, needle)"
      },
      %{name: "multiSearchAny", detail: "Any needle found", args: "(haystack, [needles])"},
      %{name: "startsWith", detail: "Check prefix", args: "(string, prefix)"},
      %{name: "endsWith", detail: "Check suffix", args: "(string, suffix)"},
      %{name: "format", detail: "Format string", args: "(pattern, args...)"},
      %{name: "base64Encode", detail: "Base64 encode", args: "(string)"},
      %{name: "base64Decode", detail: "Base64 decode", args: "(string)"},
      %{name: "normalizeQuery", detail: "Normalize SQL query", args: "(string)"},
      %{name: "normalizedQueryHash", detail: "Hash of normalized query", args: "(string)"}
    ]
  end

  defp type_conversion_functions do
    [
      %{name: "toUInt8", detail: "Convert to UInt8", args: "(value)"},
      %{name: "toUInt16", detail: "Convert to UInt16", args: "(value)"},
      %{name: "toUInt32", detail: "Convert to UInt32", args: "(value)"},
      %{name: "toUInt64", detail: "Convert to UInt64", args: "(value)"},
      %{name: "toInt8", detail: "Convert to Int8", args: "(value)"},
      %{name: "toInt16", detail: "Convert to Int16", args: "(value)"},
      %{name: "toInt32", detail: "Convert to Int32", args: "(value)"},
      %{name: "toInt64", detail: "Convert to Int64", args: "(value)"},
      %{name: "toFloat32", detail: "Convert to Float32", args: "(value)"},
      %{name: "toFloat64", detail: "Convert to Float64", args: "(value)"},
      %{name: "toDecimal32", detail: "Convert to Decimal32", args: "(value, scale)"},
      %{name: "toDecimal64", detail: "Convert to Decimal64", args: "(value, scale)"},
      %{name: "toDecimal128", detail: "Convert to Decimal128", args: "(value, scale)"},
      %{name: "toString", detail: "Convert to String", args: "(value)"},
      %{name: "toFixedString", detail: "Convert to FixedString", args: "(string, N)"},
      %{name: "toUUID", detail: "Convert to UUID", args: "(string)"},
      %{name: "toTypeName", detail: "Get type name", args: "(value)"},
      %{name: "CAST", detail: "Type cast", args: "(value AS type)"},
      %{name: "accurateCast", detail: "Accurate type cast", args: "(value, type)"},
      %{name: "accurateCastOrNull", detail: "Accurate cast or null", args: "(value, type)"},
      %{name: "toUInt32OrNull", detail: "To UInt32 or null", args: "(value)"},
      %{name: "toUInt64OrNull", detail: "To UInt64 or null", args: "(value)"},
      %{name: "toInt32OrNull", detail: "To Int32 or null", args: "(value)"},
      %{name: "toInt64OrNull", detail: "To Int64 or null", args: "(value)"},
      %{name: "toFloat64OrNull", detail: "To Float64 or null", args: "(value)"},
      %{name: "toDateOrNull", detail: "To Date or null", args: "(value)"},
      %{name: "toDateTimeOrNull", detail: "To DateTime or null", args: "(value)"},
      %{name: "toUInt32OrZero", detail: "To UInt32 or 0", args: "(value)"},
      %{name: "toUInt64OrZero", detail: "To UInt64 or 0", args: "(value)"},
      %{name: "toInt32OrZero", detail: "To Int32 or 0", args: "(value)"},
      %{name: "toInt64OrZero", detail: "To Int64 or 0", args: "(value)"},
      %{name: "toFloat64OrZero", detail: "To Float64 or 0", args: "(value)"},
      %{name: "toDateOrZero", detail: "To Date or zero-date", args: "(value)"},
      %{name: "toDateTimeOrZero", detail: "To DateTime or zero", args: "(value)"}
    ]
  end

  defp math_functions do
    [
      %{name: "abs", detail: "Absolute value", args: "(x)"},
      %{name: "e", detail: "Euler's number", args: "()"},
      %{name: "pi", detail: "Pi", args: "()"},
      %{name: "exp", detail: "Exponential", args: "(x)"},
      %{name: "log", detail: "Natural logarithm", args: "(x)"},
      %{name: "log2", detail: "Base-2 logarithm", args: "(x)"},
      %{name: "log10", detail: "Base-10 logarithm", args: "(x)"},
      %{name: "sqrt", detail: "Square root", args: "(x)"},
      %{name: "cbrt", detail: "Cube root", args: "(x)"},
      %{name: "pow", detail: "Power", args: "(x, y)"},
      %{name: "intDiv", detail: "Integer division", args: "(a, b)"},
      %{name: "intDivOrZero", detail: "Integer division or 0", args: "(a, b)"},
      %{name: "modulo", detail: "Modulo", args: "(a, b)"},
      %{name: "gcd", detail: "Greatest common divisor", args: "(a, b)"},
      %{name: "lcm", detail: "Least common multiple", args: "(a, b)"},
      %{name: "sin", detail: "Sine", args: "(x)"},
      %{name: "cos", detail: "Cosine", args: "(x)"},
      %{name: "tan", detail: "Tangent", args: "(x)"},
      %{name: "asin", detail: "Arc sine", args: "(x)"},
      %{name: "acos", detail: "Arc cosine", args: "(x)"},
      %{name: "atan", detail: "Arc tangent", args: "(x)"},
      %{name: "atan2", detail: "Arc tangent of y/x", args: "(y, x)"},
      %{name: "round", detail: "Round", args: "(x[, N])"},
      %{name: "ceil", detail: "Ceiling", args: "(x[, N])"},
      %{name: "floor", detail: "Floor", args: "(x[, N])"},
      %{name: "trunc", detail: "Truncate", args: "(x[, N])"},
      %{name: "sign", detail: "Sign of number", args: "(x)"},
      %{name: "rand", detail: "Random UInt32", args: "()"},
      %{name: "rand64", detail: "Random UInt64", args: "()"}
    ]
  end

  defp conditional_functions do
    [
      %{name: "if", detail: "Conditional", args: "(condition, then, else)"},
      %{
        name: "multiIf",
        detail: "Multi-conditional",
        args: "(cond1, then1, cond2, then2, ..., else)"
      },
      %{name: "greatest", detail: "Maximum of values", args: "(a, b)"},
      %{name: "least", detail: "Minimum of values", args: "(a, b)"},
      %{
        name: "transform",
        detail: "Transform by lookup",
        args: "(value, from_array, to_array, default)"
      }
    ]
  end

  defp hash_functions do
    [
      %{name: "halfMD5", detail: "Half MD5 hash", args: "(value)"},
      %{name: "MD5", detail: "MD5 hash", args: "(value)"},
      %{name: "sipHash64", detail: "SipHash-2-4 64-bit", args: "(value)"},
      %{name: "sipHash128", detail: "SipHash-2-4 128-bit", args: "(value)"},
      %{name: "cityHash64", detail: "CityHash 64-bit", args: "(value, ...)"},
      %{name: "SHA1", detail: "SHA-1 hash", args: "(value)"},
      %{name: "SHA256", detail: "SHA-256 hash", args: "(value)"},
      %{name: "xxHash32", detail: "xxHash 32-bit", args: "(value)"},
      %{name: "xxHash64", detail: "xxHash 64-bit", args: "(value)"},
      %{name: "murmurHash3_64", detail: "MurmurHash3 64-bit", args: "(value)"},
      %{name: "murmurHash3_128", detail: "MurmurHash3 128-bit", args: "(value)"},
      %{name: "farmHash64", detail: "FarmHash 64-bit", args: "(value)"},
      %{name: "javaHash", detail: "Java hash", args: "(value)"},
      %{name: "jumpConsistentHash", detail: "Jump consistent hash", args: "(value, buckets)"}
    ]
  end

  defp url_functions do
    [
      %{name: "protocol", detail: "Extract protocol", args: "(url)"},
      %{name: "domain", detail: "Extract domain", args: "(url)"},
      %{name: "domainWithoutWWW", detail: "Domain without www", args: "(url)"},
      %{name: "topLevelDomain", detail: "Top-level domain", args: "(url)"},
      %{name: "port", detail: "Extract port", args: "(url)"},
      %{name: "path", detail: "Extract path", args: "(url)"},
      %{name: "queryString", detail: "Extract query string", args: "(url)"},
      %{name: "fragment", detail: "Extract fragment", args: "(url)"},
      %{name: "extractURLParameter", detail: "Extract URL parameter", args: "(url, name)"},
      %{name: "extractURLParameters", detail: "Extract all URL params", args: "(url)"},
      %{name: "cutWWW", detail: "Remove www prefix", args: "(url)"},
      %{name: "cutQueryString", detail: "Remove query string", args: "(url)"},
      %{name: "cutFragment", detail: "Remove fragment", args: "(url)"},
      %{name: "decodeURLComponent", detail: "URL decode", args: "(string)"},
      %{name: "encodeURLComponent", detail: "URL encode", args: "(string)"},
      %{name: "netloc", detail: "Extract network location", args: "(url)"}
    ]
  end

  defp ip_functions do
    [
      %{name: "IPv4NumToString", detail: "IPv4 int to string", args: "(num)"},
      %{name: "IPv4StringToNum", detail: "IPv4 string to int", args: "(string)"},
      %{name: "IPv6NumToString", detail: "IPv6 binary to string", args: "(binary)"},
      %{name: "IPv6StringToNum", detail: "IPv6 string to binary", args: "(string)"},
      %{name: "toIPv4", detail: "Convert to IPv4", args: "(string)"},
      %{name: "toIPv6", detail: "Convert to IPv6", args: "(string)"},
      %{name: "isIPv4String", detail: "Check if valid IPv4", args: "(string)"},
      %{name: "isIPv6String", detail: "Check if valid IPv6", args: "(string)"},
      %{name: "IPv4CIDRToRange", detail: "CIDR to range", args: "(ipv4, prefix)"},
      %{name: "IPv6CIDRToRange", detail: "CIDR to range", args: "(ipv6, prefix)"},
      %{name: "isIPAddressInRange", detail: "Check IP in range", args: "(address, prefix)"}
    ]
  end

  defp json_functions do
    [
      %{name: "JSONExtract", detail: "Extract typed JSON value", args: "(json, path, type)"},
      %{name: "JSONExtractString", detail: "Extract JSON string", args: "(json, path)"},
      %{name: "JSONExtractUInt", detail: "Extract JSON uint", args: "(json, path)"},
      %{name: "JSONExtractInt", detail: "Extract JSON int", args: "(json, path)"},
      %{name: "JSONExtractFloat", detail: "Extract JSON float", args: "(json, path)"},
      %{name: "JSONExtractBool", detail: "Extract JSON bool", args: "(json, path)"},
      %{name: "JSONExtractRaw", detail: "Extract raw JSON", args: "(json, path)"},
      %{name: "JSONExtractArrayRaw", detail: "Extract JSON array raw", args: "(json, path)"},
      %{
        name: "JSONExtractKeysAndValues",
        detail: "Extract keys and values",
        args: "(json, path, value_type)"
      },
      %{name: "JSONExtractKeys", detail: "Extract JSON keys", args: "(json[, path])"},
      %{name: "JSONHas", detail: "Check JSON key exists", args: "(json, path)"},
      %{name: "JSONLength", detail: "JSON array/object length", args: "(json[, path])"},
      %{name: "JSONType", detail: "JSON value type", args: "(json[, path])"},
      %{name: "isValidJSON", detail: "Check valid JSON", args: "(string)"},
      %{name: "toJSONString", detail: "Convert to JSON string", args: "(value)"},
      %{
        name: "simpleJSONExtractString",
        detail: "Simple JSON string extract",
        args: "(json, field_name)"
      },
      %{
        name: "simpleJSONExtractUInt",
        detail: "Simple JSON uint extract",
        args: "(json, field_name)"
      },
      %{
        name: "simpleJSONExtractInt",
        detail: "Simple JSON int extract",
        args: "(json, field_name)"
      },
      %{
        name: "simpleJSONExtractFloat",
        detail: "Simple JSON float extract",
        args: "(json, field_name)"
      },
      %{
        name: "simpleJSONExtractBool",
        detail: "Simple JSON bool extract",
        args: "(json, field_name)"
      },
      %{name: "simpleJSONHas", detail: "Simple JSON key check", args: "(json, field_name)"}
    ]
  end

  defp encoding_functions do
    [
      %{name: "hex", detail: "Hex encode", args: "(value)"},
      %{name: "unhex", detail: "Hex decode", args: "(string)"},
      %{name: "UUIDStringToNum", detail: "UUID string to binary", args: "(string)"},
      %{name: "UUIDNumToString", detail: "UUID binary to string", args: "(binary)"},
      %{name: "generateUUIDv4", detail: "Generate UUID v4", args: "()"},
      %{name: "bitmaskToList", detail: "Bitmask to power list", args: "(num)"},
      %{name: "bitmaskToArray", detail: "Bitmask to power array", args: "(num)"},
      %{name: "bitTest", detail: "Test bit at position", args: "(num, index)"}
    ]
  end

  defp geo_functions do
    [
      %{
        name: "greatCircleDistance",
        detail: "Great-circle distance",
        args: "(lon1, lat1, lon2, lat2)"
      },
      %{name: "pointInEllipses", detail: "Point in ellipses", args: "(x, y, ellipse1, ...)"},
      %{name: "pointInPolygon", detail: "Point in polygon", args: "((x, y), polygon)"},
      %{name: "geohashEncode", detail: "Encode geohash", args: "(lon, lat[, precision])"},
      %{name: "geohashDecode", detail: "Decode geohash", args: "(geohash)"},
      %{name: "geoToH3", detail: "Convert to H3 index", args: "(lon, lat, resolution)"},
      %{name: "h3ToGeo", detail: "H3 index to coordinates", args: "(h3_index)"},
      %{name: "h3GetResolution", detail: "H3 index resolution", args: "(h3_index)"},
      %{name: "h3IsValid", detail: "Check valid H3", args: "(h3_index)"}
    ]
  end

  defp null_functions do
    [
      %{name: "isNull", detail: "Check if null", args: "(value)"},
      %{name: "isNotNull", detail: "Check if not null", args: "(value)"},
      %{name: "ifNull", detail: "If null use default", args: "(value, default)"},
      %{name: "nullIf", detail: "Null if equal", args: "(value, comparison)"},
      %{name: "assumeNotNull", detail: "Treat as non-nullable", args: "(value)"},
      %{name: "toNullable", detail: "Convert to Nullable", args: "(value)"},
      %{name: "coalesce", detail: "First non-null value", args: "(value1, value2, ...)"}
    ]
  end

  defp window_functions do
    [
      %{name: "row_number", detail: "Row number", args: "()"},
      %{name: "rank", detail: "Rank with gaps", args: "()"},
      %{name: "dense_rank", detail: "Dense rank", args: "()"},
      %{
        name: "lagInFrame",
        detail: "Previous value in frame",
        args: "(column[, offset[, default]])"
      },
      %{
        name: "leadInFrame",
        detail: "Next value in frame",
        args: "(column[, offset[, default]])"
      },
      %{name: "first_value", detail: "First value in frame", args: "(column)"},
      %{name: "last_value", detail: "Last value in frame", args: "(column)"},
      %{name: "nth_value", detail: "Nth value in frame", args: "(column, N)"},
      %{name: "ntile", detail: "Divide into buckets", args: "(N)"}
    ]
  end

  defp other_functions do
    [
      %{name: "tuple", detail: "Create tuple", args: "(value1, value2, ...)"},
      %{name: "tupleElement", detail: "Get tuple element", args: "(tuple, index)"},
      %{name: "dictGet", detail: "Get dictionary value", args: "('dict', 'attr', id)"},
      %{
        name: "dictGetOrDefault",
        detail: "Get dict value or default",
        args: "('dict', 'attr', id, default)"
      },
      %{name: "dictHas", detail: "Check dict has key", args: "('dict', id)"},
      %{name: "bar", detail: "Draw bar chart in text", args: "(x, min, max, width)"},
      %{name: "formatReadableSize", detail: "Format bytes as readable", args: "(bytes)"},
      %{name: "formatReadableQuantity", detail: "Format number as readable", args: "(number)"},
      %{name: "currentUser", detail: "Current user name", args: "()"},
      %{name: "currentDatabase", detail: "Current database name", args: "()"},
      %{name: "hostName", detail: "Server hostname", args: "()"},
      %{name: "version", detail: "Server version", args: "()"},
      %{name: "uptime", detail: "Server uptime", args: "()"},
      %{name: "materialize", detail: "Force column materialization", args: "(value)"},
      %{name: "ignore", detail: "Accept any args, return 0", args: "(...)"},
      %{name: "getSetting", detail: "Get setting value", args: "('name')"},
      %{name: "throwIf", detail: "Throw exception if true", args: "(condition[, message])"},
      %{name: "finalizeAggregation", detail: "Finalize aggregation state", args: "(state)"},
      %{name: "runningAccumulate", detail: "Running aggregate", args: "(state)"}
    ]
  end
end
