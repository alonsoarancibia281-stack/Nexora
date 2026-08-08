import 'package:flutter/material.dart';
import '../../../shared/widgets/main_navigation_scaffold.dart';
import '../../market/data/binance_market_service.dart';
import '../domain/technical_analysis.dart';
import '../services/technical_analysis_engine.dart';

class AnalyzePlaceholderScreen extends StatefulWidget {
  const AnalyzePlaceholderScreen({super.key});
  @override State<AnalyzePlaceholderScreen> createState()=>_AnalyzeScreenState();
}
class _AnalyzeScreenState extends State<AnalyzePlaceholderScreen>{
  final _service=BinanceMarketService();
  final _engine=TechnicalAnalysisEngine();
  final _symbol=TextEditingController(text:'BTCUSDT');
  String _interval='1h';
  Future<TechnicalAnalysis>? _analysis;

  @override void initState(){super.initState();_run();}
  @override void dispose(){_symbol.dispose();super.dispose();}
  void _run(){
    final symbol=_symbol.text.trim().toUpperCase();
    if(symbol.isEmpty)return;
    setState(()=>_analysis=_service.loadCandles(symbol,_interval,limit:250).then(_engine.analyze));
  }

  @override Widget build(BuildContext context)=>MainNavigationScaffold(currentIndex:2,child:Scaffold(
    appBar:AppBar(title:const Text('Analizar')),
    body:ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Motor de análisis Nexora',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
      const SizedBox(height:6),const Text('Indicadores calculados sobre velas públicas de Binance. Resultado educativo y probabilístico.'),const SizedBox(height:18),
      TextField(controller:_symbol,textCapitalization:TextCapitalization.characters,onSubmitted:(_)=>_run(),decoration:InputDecoration(labelText:'Par',hintText:'BTCUSDT',suffixIcon:IconButton(onPressed:_run,icon:const Icon(Icons.search)))),
      const SizedBox(height:12),Wrap(spacing:8,children:['15m','1h','4h','1d'].map((x)=>ChoiceChip(label:Text(x),selected:_interval==x,onSelected:(_){setState(()=>_interval=x);_run();})).toList()),const SizedBox(height:18),
      if(_analysis!=null) FutureBuilder<TechnicalAnalysis>(future:_analysis,builder:(context,s){
        if(s.connectionState!=ConnectionState.done)return const Center(child:Padding(padding:EdgeInsets.all(32),child:CircularProgressIndicator()));
        if(s.hasError)return Card(child:Padding(padding:const EdgeInsets.all(18),child:Text('No se pudo analizar el activo: ${s.error}')));
        final a=s.data!;return Column(children:[
          Card(child:Padding(padding:const EdgeInsets.all(18),child:Column(children:[Text('${a.score >= 0 ? '+' : ''}${a.score}',style:Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight:FontWeight.bold)),const Text('Nexora Score · -100 a +100'),const SizedBox(height:8),Text(a.trend,style:const TextStyle(fontWeight:FontWeight.w700)),Text('Confianza técnica ${a.confidence.toStringAsFixed(0)}% · Riesgo ${a.risk}')])),
          _section('Tendencia',[['EMA 9',a.ema9],['EMA 21',a.ema21],['EMA 50',a.ema50],['EMA 200',a.ema200],['ADX',a.adx]]),
          _section('Momentum',[['RSI 14',a.rsi],['MACD',a.macd],['Señal MACD',a.macdSignal],['Estocástico %K',a.stochasticK],['Estocástico %D',a.stochasticD]]),
          _section('Volatilidad',[['Bollinger superior',a.bollingerUpper],['Bollinger media',a.bollingerMiddle],['Bollinger inferior',a.bollingerLower],['ATR 14',a.atr],['Volatilidad %',a.volatilityPercent]]),
          _section('Niveles',[['Soporte',a.support],['Resistencia',a.resistance]]),
          const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('No es una señal de compra o venta ni garantiza resultados. Confirma el contexto, liquidez y riesgo antes de tomar decisiones.'))),
        ]);
      }),
    ]),
  ));

  Widget _section(String title,List<List<Object>> values)=>Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),const Divider(),...values.map((v)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(v[0] as String),Text((v[1] as double).toStringAsFixed(4),style:const TextStyle(fontWeight:FontWeight.w600))]))) ])));
}
