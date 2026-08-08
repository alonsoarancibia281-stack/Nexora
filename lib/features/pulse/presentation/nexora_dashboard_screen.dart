import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../market/data/binance_market_service.dart';
import '../../market/domain/candle.dart';
import '../domain/btc_5m_logistic_model.dart';
import '../domain/pulse_engine.dart';
import '../domain/pulse_ensemble_100.dart';
import '../domain/pulse_probability_calibrator.dart';
import '../domain/pulse_signal.dart';
import '../domain/pulse_statistical_engine.dart';

class NexoraDashboardScreen extends StatefulWidget {
  const NexoraDashboardScreen({super.key});
  @override
  State<NexoraDashboardScreen> createState() => _NexoraDashboardScreenState();
}

class _NexoraDashboardScreenState extends State<NexoraDashboardScreen> {
  final _service = BinanceMarketService();
  final _engine = const PulseEngine();
  final _stat = const PulseStatisticalEngine();
  final _cal = const PulseProbabilityCalibrator();
  final _ensemble = const PulseEnsemble100();
  final _logistic = const Btc5mLogisticModel();

  Timer? _clock;
  Timer? _refresh;
  Timer? _sync;
  Duration _offset = Duration.zero;
  DateTime? _roundStart;
  DateTime? _roundEnd;
  List<Candle> _candles1m = const [];
  List<Candle> _candles5m = const [];
  PulseSignal? _signal;
  PulseStatisticalResult? _statResult;
  PulseProbabilityResult? _calResult;
  PulseEnsemble100Result? _ensembleResult;
  Btc5mLogisticResult? _logisticResult;
  double _currentPrice = 0;
  double _startPrice = 0;
  double _bidVolume = 0;
  double _askVolume = 0;
  double _spreadBps = 0;
  double _micropriceEdge = 0;
  double _aggressorImbalance = 0;
  double _signedVolume = 0;
  double _tradeAcceleration = 0;
  double _priceImpulseBps = 0;
  int _tradeCount = 0;
  bool _loading = true;
  String? _error;

  DateTime get _binanceNow => DateTime.now().toUtc().add(_offset);
  int get _remainingSeconds {
    final end = _roundEnd;
    if (end == null) return 0;
    final ms = end.difference(_binanceNow).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil().clamp(0, 300);
  }
  String get _countdown => '${(_remainingSeconds ~/ 60).toString().padLeft(2,'0')}:${(_remainingSeconds % 60).toString().padLeft(2,'0')}';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _syncClock();
    _setRound();
    await _load();
    _clock = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      if (_remainingSeconds <= 0) {
        _setRound();
        _load();
      } else {
        setState(() {});
      }
    });
    _refresh = Timer.periodic(const Duration(seconds: 3), (_) => _load(silent:true));
    _sync = Timer.periodic(const Duration(seconds: 10), (_) => _syncClock());
  }

  Future<void> _syncClock() async {
    try {
      final before = DateTime.now().toUtc();
      final server = await _service.loadServerTime();
      final after = DateTime.now().toUtc();
      final midpoint = before.add(Duration(microseconds: after.difference(before).inMicroseconds ~/ 2));
      _offset = server.difference(midpoint);
    } catch (_) {}
  }

  void _setRound() {
    final now = _binanceNow;
    final m = (now.minute ~/ 5) * 5;
    _roundStart = DateTime.utc(now.year, now.month, now.day, now.hour, m);
    _roundEnd = _roundStart!.add(const Duration(minutes:5));
  }

  Future<void> _load({bool silent=false}) async {
    if (!silent && mounted) setState(() { _loading=true; _error=null; });
    try {
      final r = await Future.wait<dynamic>([
        _service.loadCandles('BTCUSDT','1m',limit:90),
        _service.loadCandles('BTCUSDT','5m',limit:60),
        _service.loadDepthMetrics('BTCUSDT',limit:100),
        _service.loadAggTradeMetrics('BTCUSDT',limit:500),
      ]);
      final c1 = r[0] as List<Candle>;
      final c5 = r[1] as List<Candle>;
      final depth = r[2] as ({double bidVolume,double askVolume,double bestBid,double bestAsk,double spreadBps,double micropriceEdge});
      final trades = r[3] as ({double aggressorImbalance,double signedVolume,double tradeAcceleration,double priceImpulseBps,int trades});
      final current = c1.last.close;
      var startPrice = 0.0;
      final start = _roundStart!;
      for (final c in c1.reversed) {
        if (c.openTime.toUtc().millisecondsSinceEpoch == start.millisecondsSinceEpoch) { startPrice=c.open; break; }
      }
      if (startPrice == 0) startPrice = current;
      final signal = _engine.analyze(candles:c1,bidVolume:depth.bidVolume,askVolume:depth.askVolume,roundStartPrice:startPrice,secondsRemaining:_remainingSeconds);
      final stat = _stat.analyze(candles:c1,bidVolume:depth.bidVolume,askVolume:depth.askVolume,roundStartPrice:startPrice,secondsRemaining:_remainingSeconds);
      final cal = _cal.calibrate(score:signal.score,instability:signal.instabilityScore,agreement:signal.agreementRatio,roundDistancePct:signal.roundDistancePct,expectedRemainingMovePct:signal.expectedRemainingMovePct,secondsRemaining:_remainingSeconds);
      final input = _analystInput(c1, signal, stat, startPrice, depth, trades);
      final ensemble = _ensemble.analyze(input);
      final completed5m = c5.where((c)=>c.openTime.toUtc().isBefore(start)).toList(growable:false);
      final logistic = _logistic.analyze(completed5m);
      if (!mounted) return;
      setState(() {
        _candles1m=c1; _candles5m=c5; _signal=signal; _statResult=stat; _calResult=cal; _ensembleResult=ensemble; _logisticResult=logistic;
        _currentPrice=current; _startPrice=startPrice; _bidVolume=depth.bidVolume; _askVolume=depth.askVolume; _spreadBps=depth.spreadBps; _micropriceEdge=depth.micropriceEdge;
        _aggressorImbalance=trades.aggressorImbalance; _signedVolume=trades.signedVolume; _tradeAcceleration=trades.tradeAcceleration; _priceImpulseBps=trades.priceImpulseBps; _tradeCount=trades.trades;
        _loading=false; _error=null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading=false; _error='No se pudieron actualizar los datos reales de Binance.'; });
    }
  }

  AnalystInput _analystInput(List<Candle> candles, PulseSignal signal, PulseStatisticalResult stat, double startPrice,
      ({double bidVolume,double askVolume,double bestBid,double bestAsk,double spreadBps,double micropriceEdge}) depth,
      ({double aggressorImbalance,double signedVolume,double tradeAcceleration,double priceImpulseBps,int trades}) trades) {
    double norm(double v,double scale)=>scale==0?0:(v/scale).clamp(-1.0,1.0).toDouble();
    final closes=candles.map((c)=>c.close).toList(); final current=closes.last;
    final shortReturn=closes.length<4?0.0:(current-closes[closes.length-4])/closes[closes.length-4]*100;
    final prevReturn=closes.length<7?0.0:(closes[closes.length-4]-closes[closes.length-7])/closes[closes.length-7]*100;
    final recent=candles.sublist(math.max(0,candles.length-20));
    final mean=recent.map((c)=>c.close).reduce((a,b)=>a+b)/recent.length;
    final variance=recent.map((c)=>math.pow(c.close-mean,2).toDouble()).reduce((a,b)=>a+b)/recent.length;
    final sigma=math.sqrt(variance); final z=sigma<=0?0.0:((current-mean)/sigma).clamp(-3.0,3.0)/3.0;
    final total=depth.bidVolume+depth.askVolume; final book=total<=0?0.0:(depth.bidVolume-depth.askVolume)/total;
    final roundEdge=(current-startPrice)/startPrice*100;
    final recentRanges=recent.map((c)=>c.high-c.low).toList(); final avgRange=recentRanges.reduce((a,b)=>a+b)/recentRanges.length;
    final rangeExpansion=avgRange<=0?0.0:(((candles.last.high-candles.last.low)/avgRange)-1).clamp(-1.0,1.0).toDouble();
    return AnalystInput(instability:signal.instabilityScore,secondsRemaining:_remainingSeconds,features:{
      'momentum':signal.momentumScore/100,'acceleration':norm(shortReturn-prevReturn,.18),'shortReturn':norm(shortReturn,.30),
      'trend':signal.trendScore/100,'emaSpread':signal.trendScore/100,'slope':norm(stat.driftPerMinute*100,.05),
      'volatilityBreakout':norm(trades.priceImpulseBps,8),'atrExpansion':rangeExpansion,'rangeExpansion':rangeExpansion,
      'zPrice':z,'vwapDistance':norm(roundEdge,.35),'bookImbalance':book.clamp(-1.0,1.0).toDouble(),
      'micropriceEdge':norm(depth.micropriceEdge,2),'spreadPressure':-norm(depth.spreadBps,3),
      'aggressorImbalance':trades.aggressorImbalance,'tradeAcceleration':trades.tradeAcceleration*trades.aggressorImbalance.sign,
      'signedVolume':trades.signedVolume,'volumeZ':norm(signal.volumeRatio-1,1.5),'obvSlope':trades.signedVolume,
      'volumePriceAgreement':trades.signedVolume*(signal.momentumScore==0?0:signal.momentumScore.sign),
      'bodyPressure':signal.bodyPressure/100,'breakoutQuality':norm(trades.priceImpulseBps,10),'wickBias':signal.bodyPressure/100,
      'regimeTrend':signal.trendScore/100,'regimePersistence':stat.autocorrelation,'roundEdge':norm(roundEdge,math.max(signal.expectedRemainingMovePct,.05)),
    });
  }

  double get _probabilityUp {
    final e=_ensembleResult, s=_statResult, c=_calResult, l=_logisticResult;
    var sum=0.0,w=0.0;
    if(e!=null){sum+=e.probabilityUp*.50;w+=.50;}
    if(s!=null){sum+=s.probabilityUp*.28;w+=.28;}
    if(c!=null){sum+=c.probabilityUp*.17;w+=.17;}
    if(l!=null&&l.isReady){sum+=l.probabilityUp*.05;w+=.05;}
    return w==0?.5:(sum/w).clamp(.08,.92).toDouble();
  }
  bool get _up => _probabilityUp>=.5;
  double get _confidence => math.max(_probabilityUp,1-_probabilityUp)*100;
  double get _bookImbalance { final t=_bidVolume+_askVolume; return t<=0?0:(_bidVolume-_askVolume)/t; }

  @override
  Widget build(BuildContext context) {
    final e=_ensembleResult, s=_signal, st=_statResult;
    return Scaffold(
      appBar: AppBar(title: const Text('NEXORA · BTC/USDT'), actions:[Padding(padding:const EdgeInsets.only(right:16),child:Center(child:Text(_countdown,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:18))))]),
      body: RefreshIndicator(onRefresh:()=>_load(),child:ListView(padding:const EdgeInsets.all(12),children:[
        if(_error!=null) _card('CONEXIÓN',Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        _card('PREDICCIÓN NEXORA',Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(_up?'ALTA ↑':'BAJA ↓',style:TextStyle(fontSize:38,fontWeight:FontWeight.w800,color:_up?const Color(0xFF43F27A):const Color(0xFFFF5A67))),Text('${_confidence.toStringAsFixed(1)}%',style:const TextStyle(fontSize:32,fontWeight:FontWeight.bold))]),
          const SizedBox(height:8),Text('BTC/USDT ${_currentPrice==0?'—':_currentPrice.toStringAsFixed(2)} · Inicio ${_startPrice==0?'—':_startPrice.toStringAsFixed(2)}'),
          const SizedBox(height:8),LinearProgressIndicator(value:(_confidence/100).clamp(0,1)),
          const SizedBox(height:8),Text(_loading?'Actualizando datos reales…':'Probabilidad fusionada de motores matemáticos y 100 analistas.'),
        ])),
        if(_candles5m.isNotEmpty) _card('GRÁFICO BTC/USDT · 5M',SizedBox(height:220,child:CustomPaint(painter:_CandlePainter(_candles5m.takeLast(28).toList())))),
        _card('100 ANALISTAS',Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(e==null?'Sin datos todavía':'${e.activeAnalysts} analistas activos · ${(e.agreement*100).toStringAsFixed(0)}% de acuerdo',style:const TextStyle(fontSize:18,fontWeight:FontWeight.bold)),
          const SizedBox(height:10),if(e!=null)...e.teamOpinions.map((t)=>_metric(_familyName(t.family),'${(t.probabilityUp*100).toStringAsFixed(1)}% ALTA · calidad ${(t.quality*100).toStringAsFixed(0)}%')),
        ])),
        _card('MICROESTRUCTURA BINANCE',Column(children:[
          _metric('Desequilibrio libro','${(_bookImbalance*100).toStringAsFixed(1)}%'),
          _metric('Spread','${_spreadBps.toStringAsFixed(3)} bps'),
          _metric('Microprecio','${_micropriceEdge.toStringAsFixed(3)} bps'),
          _metric('Aggressor imbalance','${(_aggressorImbalance*100).toStringAsFixed(1)}%'),
          _metric('Volumen firmado','${(_signedVolume*100).toStringAsFixed(1)}%'),
          _metric('Aceleración trades','${(_tradeAcceleration*100).toStringAsFixed(1)}%'),
          _metric('Impulso precio','${_priceImpulseBps.toStringAsFixed(2)} bps'),
          _metric('Trades muestreados','$_tradeCount'),
        ])),
        _card('RÉGIMEN Y ESTADÍSTICA',Column(children:[
          _metric('Estado',s?.stabilityLabel ?? '—'),
          _metric('Instabilidad',s==null?'—':'${s.instabilityScore.toStringAsFixed(1)}%'),
          _metric('Tendencia',s==null?'—':s.trendScore.toStringAsFixed(1)),
          _metric('Momentum',s==null?'—':s.momentumScore.toStringAsFixed(1)),
          _metric('Confluencia',s==null?'—':'${(s.agreementRatio*100).toStringAsFixed(0)}%'),
          _metric('EWMA volatilidad',st==null?'—':st.ewmaVolatilityPerMinute.toStringAsExponential(3)),
          _metric('Autocorrelación',st==null?'—':st.autocorrelation.toStringAsFixed(3)),
          _metric('Calidad estadística',st==null?'—':'${(st.signalQuality*100).toStringAsFixed(0)}%'),
        ])),
        _card('MARCO DE CONOCIMIENTO',Column(children:[
          _metric('Margen de seguridad',s==null?'—':(s.instabilityScore<38&&_confidence>=55?'OK':'CAUTELOSO')),
          _metric('Ranking multifactor',e==null?'—':'10 equipos ponderados por calidad'),
          _metric('Confirmación de mercado',_priceImpulseBps.abs()>=2?'ACTIVA':'DÉBIL'),
          _metric('Breakout / Darvas',_priceImpulseBps.abs()>=8?'POSIBLE RUPTURA':'SIN RUPTURA FUERTE'),
          _metric('Random-walk / Taleb','PENDIENTE DE HISTORIAL REAL'),
          _metric('Brier / Log loss','PENDIENTE DE RONDAS CERRADAS'),
        ])),
        _card('HISTORIAL Y RENDIMIENTO',const Text('No se muestran estadísticas simuladas. Accuracy, Brier Score, log loss y ventaja frente al azar aparecerán cuando Nexora haya registrado suficientes rondas reales cerradas.')),
        const SizedBox(height:16),const Text('Nexora es un sistema experimental de análisis probabilístico. No garantiza resultados ni ejecuta operaciones automáticamente.',textAlign:TextAlign.center,style:TextStyle(fontSize:12)),
      ])),
    );
  }

  Widget _card(String title, Widget child)=>Card(child:Padding(padding:const EdgeInsets.all(14),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w800,letterSpacing:1.1)),const SizedBox(height:12),child])));
  Widget _metric(String a,String b)=>Padding(padding:const EdgeInsets.symmetric(vertical:4),child:Row(children:[Expanded(child:Text(a,style:TextStyle(color:Colors.white.withValues(alpha:.72)))),const SizedBox(width:10),Flexible(child:Text(b,textAlign:TextAlign.right,style:const TextStyle(fontWeight:FontWeight.w600)))]));
  String _familyName(AnalystFamily f)=>switch(f){AnalystFamily.momentum=>'Momentum',AnalystFamily.trend=>'Tendencia',AnalystFamily.volatility=>'Volatilidad',AnalystFamily.meanReversion=>'Reversión media',AnalystFamily.orderBook=>'Order book',AnalystFamily.tradeFlow=>'Trade flow',AnalystFamily.volume=>'Volumen',AnalystFamily.priceAction=>'Price action',AnalystFamily.intermarket=>'Intermercado',AnalystFamily.regime=>'Régimen'};

  @override void dispose(){_clock?.cancel();_refresh?.cancel();_sync?.cancel();super.dispose();}
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles); final List<Candle> candles;
  @override void paint(Canvas canvas, Size size){
    if(candles.isEmpty)return;
    final hi=candles.map((c)=>c.high).reduce(math.max),lo=candles.map((c)=>c.low).reduce(math.min),range=math.max(hi-lo,.0001);
    final step=size.width/candles.length,bodyW=math.max(2.0,step*.55);
    final grid=Paint()..color=const Color(0xFF17313A)..strokeWidth=1;
    for(var i=1;i<5;i++){final y=size.height*i/5;canvas.drawLine(Offset(0,y),Offset(size.width,y),grid);}
    double y(double p)=>size.height-(p-lo)/range*size.height;
    for(var i=0;i<candles.length;i++){
      final c=candles[i],x=step*i+step/2,up=c.close>=c.open;
      final paint=Paint()..color=up?const Color(0xFF43F27A):const Color(0xFFFF5A67)..strokeWidth=1.2;
      canvas.drawLine(Offset(x,y(c.high)),Offset(x,y(c.low)),paint);
      final top=math.min(y(c.open),y(c.close)),bottom=math.max(y(c.open),y(c.close));
      canvas.drawRect(Rect.fromLTRB(x-bodyW/2,top,x+bodyW/2,math.max(bottom,top+1.5)),paint);
    }
  }
  @override bool shouldRepaint(covariant _CandlePainter oldDelegate)=>true;
}

extension _TakeLast<T> on Iterable<T>{Iterable<T> takeLast(int n){final l=toList(growable:false);return l.skip(math.max(0,l.length-n));}}
