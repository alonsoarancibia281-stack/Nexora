class Candle {
  const Candle({required this.openTime,required this.open,required this.high,required this.low,required this.close,required this.volume});
  final DateTime openTime; final double open,high,low,close,volume;
  factory Candle.fromBinance(List<dynamic> row)=>Candle(openTime:DateTime.fromMillisecondsSinceEpoch(row[0] as int),open:double.parse('${row[1]}'),high:double.parse('${row[2]}'),low:double.parse('${row[3]}'),close:double.parse('${row[4]}'),volume:double.parse('${row[5]}'));
}
