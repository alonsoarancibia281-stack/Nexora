import 'dart:math' as math;

import '../../market/domain/candle.dart';
import 'pulse_realized_volatility.dart';
import 'pulse_signal.dart';

class PulseEngine {
  const PulseEngine();

  PulseSignal analyze({
    required List<Candle> candles,
    required double bidVolume,
    required double askVolume,
    double? roundStartPrice,
    int secondsRemaining = 300,
  }) {
    if (candles.length < 30) throw ArgumentError('Se requieren al menos 30 velas de 1 minuto.');
    final recent = candles.sublist(candles.length - 30);
    final closes = recent.map((e) => e.close).toList();
    final volumes = recent.map((e) => e.volume).toList();
    final currentPrice = closes.last;
    final safeSeconds = secondsRemaining.clamp(0, 300);
    double pct(double from,double to)=>from==0?0.0:((to-from)/from)*100;
    double norm(double value,double scale)=>scale==0?0.0:(value/scale).clamp(-1.0,1.0).toDouble();

    final momentum1=pct(closes[closes.length-2],closes.last);
    final momentum3=pct(closes[closes.length-4],closes.last);
    final momentum5=pct(closes[closes.length-6],closes.last);
    final momentumScore=(norm(momentum1,.16)*.25+norm(momentum3,.34)*.45+norm(momentum5,.58)*.30).clamp(-1.0,1.0).toDouble();
    final ema5=_ema(closes,5),ema13=_ema(closes,13),ema21=_ema(closes,21);
    final trendPct=ema13==0?0.0:((ema5-ema13)/ema13)*100;
    final trendLongPct=ema21==0?0.0:((ema13-ema21)/ema21)*100;
    final slopePct=_slopePctPerCandle(closes.sublist(closes.length-9));
    final trendScore=(norm(trendPct,.20)*.45+norm(trendLongPct,.24)*.20+norm(slopePct,.055)*.35).clamp(-1.0,1.0).toDouble();
    final rsi=_rsi(closes,14),rsiScore=norm(_rsi(closes,14)-50,19);
    final vwap=_vwap(recent.sublist(recent.length-20));
    final vwapScore=norm(pct(vwap,currentPrice),.26);
    final rangeCandles=recent.sublist(recent.length-12);
    final rangeHigh=rangeCandles.map((e)=>e.high).reduce(math.max),rangeLow=rangeCandles.map((e)=>e.low).reduce(math.min);
    final rangeSpan=rangeHigh-rangeLow;
    final rangePosition=rangeSpan<=0?0.0:(((currentPrice-rangeLow)/rangeSpan)*2-1).clamp(-1.0,1.0).toDouble();
    final persistenceCandles=recent.sublist(recent.length-7);
    var persistence=0.0;
    for(final c in persistenceCandles){if(c.close>c.open)persistence++;else if(c.close<c.open)persistence--;}
    persistence=(persistence/persistenceCandles.length).clamp(-1.0,1.0).toDouble();
    final depthTotal=bidVolume+askVolume;
    final imbalance=depthTotal<=0?0.0:((bidVolume-askVolume)/depthTotal).clamp(-1.0,1.0).toDouble();
    final recentVol=volumes.sublist(volumes.length-4).reduce((a,b)=>a+b)/4;
    final baselineVol=volumes.sublist(5,20).reduce((a,b)=>a+b)/15;
    final volumeRatio=baselineVol<=0?1.0:recentVol/baselineVol;
    final volumeImpulse=(((volumeRatio-1)/1.35).clamp(-1.0,1.0).toDouble())*(momentumScore==0?0.0:momentumScore.sign);
    var bodyPressure=0.0,wickNoise=0.0;
    final pressureCandles=recent.sublist(recent.length-6);
    for(final c in pressureCandles){final range=c.high-c.low;if(range>0){final body=(c.close-c.open).abs();bodyPressure+=((c.close-c.open)/range).clamp(-1.0,1.0);wickNoise+=(1-body/range).clamp(0.0,1.0);}}
    bodyPressure=(bodyPressure/pressureCandles.length).clamp(-1.0,1.0).toDouble();wickNoise=(wickNoise/pressureCandles.length).clamp(0.0,1.0).toDouble();
    final atrPct=_atrPct(recent,14);
    // σ of the diffusion anchor. It used to be the ATR times a hand-picked
    // 0.72, which fitted against 8639 real rounds with a coefficient of
    // 0.7754 ± 0.0266 — the anchor was overconfident because the true range is
    // not the standard deviation of returns and their ratio moves with the
    // regime. The EWMA of one-minute log returns fits at 0.9943 ± 0.0336,
    // indistinguishable from the 1.00 a well-calibrated probability demands,
    // and it carries no free constants.
    const volatility=PulseRealizedVolatility();
    final expectedRemainingMovePct=volatility.scale(volatility.ewmaPerMinutePct(candles),safeSeconds);
    var roundEdgeScore=0.0,roundDistancePct=0.0;
    if(roundStartPrice!=null&&roundStartPrice>0){roundDistancePct=pct(roundStartPrice,currentPrice);roundEdgeScore=norm(roundDistancePct,expectedRemainingMovePct);}
    final elapsedRatio=1-safeSeconds/300.0;
    final roundEdgeWeight=roundStartPrice==null?0.0:(.10+elapsedRatio*.28).clamp(.10,.38).toDouble();
    final technicalRaw=(momentumScore*.20+trendScore*.18+rsiScore*.08+vwapScore*.12+rangePosition*.08+persistence*.08+imbalance*.10+volumeImpulse*.08+bodyPressure*.08).clamp(-1.0,1.0).toDouble();
    final raw=(technicalRaw*(1-roundEdgeWeight)+roundEdgeScore*roundEdgeWeight).clamp(-1.0,1.0).toDouble();
    final score=raw*100;
    final components=<double>[momentumScore,trendScore,rsiScore,vwapScore,rangePosition,persistence,imbalance,bodyPressure,if(roundStartPrice!=null)roundEdgeScore];
    final meaningful=components.where((v)=>v.abs()>=.12).toList();
    final targetSign=raw==0?0.0:raw.sign;
    final agreementRatio=meaningful.isEmpty?0.0:meaningful.where((v)=>v.sign==targetSign).length/meaningful.length;
    final momentumVsBookConflict=momentumScore.abs()>.24&&imbalance.abs()>.20&&momentumScore.sign!=imbalance.sign;
    final trendVsMomentumConflict=trendScore.abs()>.25&&momentumScore.abs()>.25&&trendScore.sign!=momentumScore.sign;
    final edgeVsTrendConflict=roundStartPrice!=null&&roundEdgeScore.abs()>.30&&trendScore.abs()>.25&&roundEdgeScore.sign!=trendScore.sign;
    var flips=0;int cd(Candle c)=>c.close>c.open?1:c.close<c.open?-1:0;final fc=recent.sublist(recent.length-8);var prev=cd(fc.first);for(final c in fc.skip(1)){final cur=cd(c);if(prev!=0&&cur!=0&&prev!=cur)flips++;if(cur!=0)prev=cur;}
    final conflictCount=[momentumVsBookConflict,trendVsMomentumConflict,edgeVsTrendConflict].where((v)=>v).length;
    final atrInstability=((atrPct-.10)/.55).clamp(0.0,1.0).toDouble(),volumeShock=((volumeRatio-1.25)/1.75).clamp(0.0,1.0).toDouble();
    final instabilityScore=(atrInstability*.34+(flips/(fc.length-1))*.25+wickNoise*.20+(conflictCount/3)*.16+volumeShock*.05)*100;
    final stability=instabilityScore>=68?MarketStability.veryUnstable:instabilityScore>=38?MarketStability.unstable:MarketStability.stable;
    var confidence=50+score.abs()*.34+agreementRatio*13;
    if(momentumVsBookConflict)confidence-=6;if(trendVsMomentumConflict)confidence-=7;if(edgeVsTrendConflict)confidence-=6;if(volumeRatio<.70)confidence-=5;if(rsi>=78||rsi<=22)confidence-=3;if(atrPct<.045)confidence-=6;if(atrPct>.95)confidence-=5;if(stability==MarketStability.unstable)confidence-=7;if(stability==MarketStability.veryUnstable)confidence-=14;
    confidence=confidence.clamp(50.0,91.0).toDouble();
    final lowQuality=score.abs()<28||confidence<64||agreementRatio<.56||volumeRatio<.48||stability==MarketStability.veryUnstable||(stability==MarketStability.unstable&&score.abs()<42);
    final direction=lowQuality?PulseDirection.noTrade:score>0?PulseDirection.up:PulseDirection.down;
    return PulseSignal(direction:direction,score:score,confidence:confidence,momentumScore:momentumScore*100,trendScore:trendScore*100,orderBookImbalance:imbalance*100,volumeRatio:volumeRatio,bodyPressure:bodyPressure*100,instabilityScore:instabilityScore,stability:stability,agreementRatio:agreementRatio,roundDistancePct:roundDistancePct,expectedRemainingMovePct:expectedRemainingMovePct,reasons:['RSI ${rsi.toStringAsFixed(1)} · confluencia ${(agreementRatio*100).toStringAsFixed(0)}%','Movimiento esperado restante ${expectedRemainingMovePct.toStringAsFixed(3)}%.']);
  }

  double _ema(List<double> v,int p){final k=2.0/(p+1);var e=v.first;for(final x in v.skip(1)){e=x*k+e*(1-k);}return e;}
  double _rsi(List<double> c,int p){if(c.length<=p)return 50;var g=0.0,l=0.0;for(var i=c.length-p;i<c.length;i++){final d=c[i]-c[i-1];if(d>0)g+=d;else l-=d;}if(l==0)return g==0?50:100;final rs=g/l;return 100-(100/(1+rs));}
  double _vwap(List<Candle> cs){var pv=0.0,v=0.0;for(final c in cs){pv+=((c.high+c.low+c.close)/3)*c.volume;v+=c.volume;}return v<=0?cs.last.close:pv/v;}
  double _atrPct(List<Candle> cs,int p){final start=math.max(1,cs.length-p);var total=0.0,n=0;for(var i=start;i<cs.length;i++){final c=cs[i],pc=cs[i-1].close;total+=math.max(c.high-c.low,math.max((c.high-pc).abs(),(c.low-pc).abs()));n++;}return n==0||cs.last.close==0?0:(total/n)/cs.last.close*100;}
  double _slopePctPerCandle(List<double> v){if(v.length<2||v.last==0)return 0;final n=v.length.toDouble();var sx=0.0,sy=0.0,sxy=0.0,sxx=0.0;for(var i=0;i<v.length;i++){final x=i.toDouble(),y=v[i];sx+=x;sy+=y;sxy+=x*y;sxx+=x*x;}final d=n*sxx-sx*sx;if(d==0)return 0;return ((n*sxy-sx*sy)/d)/v.last*100;}
}
