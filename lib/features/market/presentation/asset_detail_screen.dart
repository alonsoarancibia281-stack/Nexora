import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/binance_market_service.dart';
import '../domain/candle.dart';
import '../widgets/candlestick_chart.dart';

class AssetDetailScreen extends StatefulWidget {
  const AssetDetailScreen({super.key,required this.symbol}); final String symbol;
  @override State<AssetDetailScreen> createState()=>_AssetDetailScreenState();
}
class _AssetDetailScreenState extends State<AssetDetailScreen>{
  final service=BinanceMarketService(); String interval='1h'; late Future<List<Candle>> candles;
  @override void initState(){super.initState();candles=service.loadCandles(widget.symbol,interval);}
  void changeInterval(String value){setState((){interval=value;candles=service.loadCandles(widget.symbol,interval);});}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text(widget.symbol)),body:ListView(padding:const EdgeInsets.all(16),children:[
    StreamBuilder<double>(stream:service.livePrice(widget.symbol),builder:(context,snapshot)=>Text(snapshot.hasData?'${snapshot.data!.toStringAsPrecision(8)} USDT':'Conectando precio en tiempo real…',style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold))),
    const SizedBox(height:8),const Text('Datos públicos de mercado. No constituye una recomendación de inversión.'),const SizedBox(height:20),
    Wrap(spacing:8,children:['5m','15m','1h','4h','1d','1w'].map((x)=>ChoiceChip(label:Text(x),selected:interval==x,onSelected:(_)=>changeInterval(x))).toList()),const SizedBox(height:18),
    FutureBuilder<List<Candle>>(future:candles,builder:(context,snapshot){if(snapshot.connectionState!=ConnectionState.done)return const SizedBox(height:260,child:Center(child:CircularProgressIndicator()));if(snapshot.hasError)return SizedBox(height:260,child:Center(child:Text('No se pudieron cargar las velas: ${snapshot.error}')));return Card(child:Padding(padding:const EdgeInsets.all(12),child:CandlestickChart(candles:snapshot.data??const [])));}),
    const SizedBox(height:16),const Card(child:Padding(padding:EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Próximo paso: análisis técnico',style:TextStyle(fontWeight:FontWeight.bold)),SizedBox(height:6),Text('RSI, MACD, EMA, Bollinger, ATR, ADX, soportes y resistencias se incorporarán en la Fase 3 sobre estas velas reales.')]))),
  ]));
}
