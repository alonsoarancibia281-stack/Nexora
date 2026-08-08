import 'package:flutter/material.dart';
import '../domain/candle.dart';

class CandlestickChart extends StatelessWidget {
  const CandlestickChart({super.key,required this.candles});
  final List<Candle> candles;
  @override Widget build(BuildContext context)=>SizedBox(height:260,width:double.infinity,child:CustomPaint(painter:_CandlePainter(candles)));
}

class _CandlePainter extends CustomPainter {
  _CandlePainter(this.candles); final List<Candle> candles;
  @override void paint(Canvas canvas,Size size){if(candles.isEmpty)return;final minLow=candles.map((e)=>e.low).reduce((a,b)=>a<b?a:b);final maxHigh=candles.map((e)=>e.high).reduce((a,b)=>a>b?a:b);final range=(maxHigh-minLow)==0?1:maxHigh-minLow;final step=size.width/candles.length;double y(double p)=>size.height-((p-minLow)/range)*size.height;for(var i=0;i<candles.length;i++){final c=candles[i];final x=i*step+step/2;final rising=c.close>=c.open;final paint=Paint()..color=rising?Colors.greenAccent:Colors.redAccent..strokeWidth=1.2;canvas.drawLine(Offset(x,y(c.high)),Offset(x,y(c.low)),paint);final top=y(rising?c.close:c.open),bottom=y(rising?c.open:c.close);canvas.drawRect(Rect.fromLTRB(x-step*.28,top,x+step*.28,bottom==top?bottom+1:bottom),paint);} }
  @override bool shouldRepaint(covariant _CandlePainter oldDelegate)=>oldDelegate.candles!=candles;
}
