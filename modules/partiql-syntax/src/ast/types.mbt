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
  Decimal(Int?, Int?)
  Numeric(Int?, Int?)
  Real
  /// `DOUBLE PRECISION`, or `FLOAT(p)` with its precision.
  Double(Int?)
  Char(Int?)
  Varchar(Int?)
  String
  Symbol
  Blob
  Clob
  Date
  Time(Int?, with_tz~ : Bool)
  Timestamp(Int?, with_tz~ : Bool)
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
