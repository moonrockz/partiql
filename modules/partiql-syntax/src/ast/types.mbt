///|
/// A data type in CAST, IS and type positions.
pub(all) enum DataType {
  Null
  Missing
  Bool
  TinyInt
  SmallInt
  Int
  BigInt
  Decimal(Int32?, Int32?)
  Numeric(Int32?, Int32?)
  Real
  /// `DOUBLE PRECISION`, or `FLOAT(p)` with its precision.
  Double(Int32?)
  Char(Int32?)
  Varchar(Int32?)
  String
  Symbol
  Blob
  Clob
  Date
  Time(Int32?, with_tz~ : Bool)
  Timestamp(Int32?, with_tz~ : Bool)
  Interval(IntervalQualifier)
  Struct
  Tuple
  List
  Bag
  Sexp
  Any
  Map(DataType, DataType)
  Array(DataType?)
  Custom(Identifier)
} derive(Debug, Eq)
