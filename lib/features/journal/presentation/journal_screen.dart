import 'package:flutter/material.dart';
import '../data/local_journal_repository.dart';
import '../domain/journal_entry.dart';

class JournalScreen extends StatefulWidget {
  const JournalScreen({super.key});
  @override State<JournalScreen> createState()=>_JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen>{
  final repo=LocalJournalRepository();
  final symbol=TextEditingController(text:'BTCUSDT');
  final thesis=TextEditingController();
  final pnl=TextEditingController();
  String outcome='Pendiente';
  List<JournalEntry> entries=[];
  bool loading=true;

  @override void initState(){super.initState();_load();}
  Future<void> _load() async {final data=await repo.load();if(mounted)setState((){entries=data;loading=false;});}
  Future<void> _add() async {
    final pair=symbol.text.trim().toUpperCase();
    final note=thesis.text.trim();
    if(pair.isEmpty||note.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Ingresa un par y una nota o tesis.')));return;}
    final entry=JournalEntry(id:DateTime.now().microsecondsSinceEpoch.toString(),symbol:pair,thesis:note,createdAt:DateTime.now(),outcome:outcome,pnlPercent:double.tryParse(pnl.text.replaceAll(',','.')));
    await repo.add(entry);thesis.clear();pnl.clear();setState(()=>outcome='Pendiente');await _load();
  }

  @override Widget build(BuildContext context){
    final completed=entries.where((e)=>e.outcome!='Pendiente').toList();
    final wins=completed.where((e)=>(e.pnlPercent??0)>0).length;
    final avg=completed.isEmpty?0.0:completed.map((e)=>e.pnlPercent??0).reduce((a,b)=>a+b)/completed.length;
    return Scaffold(appBar:AppBar(title:const Text('Diario de trading')),body:ListView(padding:const EdgeInsets.all(16),children:[
      const Text('Registra ideas y resultados simulados. Este diario no ejecuta operaciones.'),
      const SizedBox(height:16),
      Row(children:[Expanded(child:_Metric(label:'Entradas',value:'${entries.length}')),const SizedBox(width:8),Expanded(child:_Metric(label:'Aciertos',value:completed.isEmpty?'—':'${(wins/completed.length*100).toStringAsFixed(0)}%')),const SizedBox(width:8),Expanded(child:_Metric(label:'PnL medio',value:completed.isEmpty?'—':'${avg.toStringAsFixed(2)}%'))]),
      const SizedBox(height:16),
      TextField(controller:symbol,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'Par',border:OutlineInputBorder())),
      const SizedBox(height:12),
      TextField(controller:thesis,maxLines:3,decoration:const InputDecoration(labelText:'Tesis / motivo / aprendizaje',border:OutlineInputBorder())),
      const SizedBox(height:12),
      DropdownButtonFormField<String>(initialValue:outcome,decoration:const InputDecoration(labelText:'Resultado',border:OutlineInputBorder()),items:['Pendiente','Ganancia','Pérdida','Neutral'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>outcome=v??'Pendiente')),
      const SizedBox(height:12),
      TextField(controller:pnl,keyboardType:const TextInputType.numberWithOptions(decimal:true,signed:true),decoration:const InputDecoration(labelText:'PnL % (opcional)',border:OutlineInputBorder())),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:_add,icon:const Icon(Icons.note_add_outlined),label:const Text('Guardar entrada')),
      const SizedBox(height:20),
      if(loading)const Center(child:CircularProgressIndicator()) else if(entries.isEmpty)const Card(child:Padding(padding:EdgeInsets.all(18),child:Text('Aún no hay entradas.'))) else ...entries.map((e)=>Card(child:ListTile(title:Text('${e.symbol} · ${e.outcome}'),subtitle:Text('${e.thesis}\n${e.createdAt.toLocal()}${e.pnlPercent==null?'':' · ${e.pnlPercent!.toStringAsFixed(2)}%'}'),isThreeLine:true,trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()async{await repo.remove(e.id);await _load();}))))),
    ]));
  }

  @override void dispose(){symbol.dispose();thesis.dispose();pnl.dispose();super.dispose();}
}

class _Metric extends StatelessWidget{const _Metric({required this.label,required this.value});final String label,value;@override Widget build(BuildContext context)=>Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label,style:Theme.of(context).textTheme.bodySmall),const SizedBox(height:4),Text(value,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold))])));}
