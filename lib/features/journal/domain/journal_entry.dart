class JournalEntry {
  const JournalEntry({required this.id,required this.symbol,required this.thesis,required this.createdAt,this.outcome='Pendiente',this.pnlPercent});
  final String id;
  final String symbol;
  final String thesis;
  final DateTime createdAt;
  final String outcome;
  final double? pnlPercent;

  Map<String,dynamic> toJson()=>{'id':id,'symbol':symbol,'thesis':thesis,'createdAt':createdAt.toIso8601String(),'outcome':outcome,'pnlPercent':pnlPercent};
  factory JournalEntry.fromJson(Map<String,dynamic> j)=>JournalEntry(id:j['id'] as String,symbol:j['symbol'] as String,thesis:j['thesis'] as String,createdAt:DateTime.parse(j['createdAt'] as String),outcome:j['outcome'] as String? ?? 'Pendiente',pnlPercent:(j['pnlPercent'] as num?)?.toDouble());
}
