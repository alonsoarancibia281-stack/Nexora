import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double progress = .08;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 90), (t) {
      if (!mounted) return;
      setState(() => progress = (progress + .035).clamp(0, 1));
      if (progress >= 1) {
        t.cancel();
        Future.delayed(const Duration(milliseconds: 180), () {
          if (mounted) context.go('/home');
        });
      }
    });
  }

  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment.topCenter, radius: 1.2,
          colors: [Color(0xFF07392E), Color(0xFF061D2B), Color(0xFF03070D)]),
      ),
      child: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const _NexoraMark(size: 150),
          const SizedBox(height: 28),
          const Text('NEXORA', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w700, letterSpacing: 9)),
          const SizedBox(height: 8),
          Text('META-MOTOR DE 100 ANALISTAS', style: TextStyle(fontSize: 12, letterSpacing: 2.2, color: Colors.white.withValues(alpha:.72))),
          const SizedBox(height: 44),
          const Wrap(alignment: WrapAlignment.center, spacing: 18, runSpacing: 12, children: [
            _Feature(icon: Icons.psychology_alt_outlined,label:'100 ANALISTAS'),
            _Feature(icon: Icons.query_stats,label:'ANÁLISIS'),
            _Feature(icon: Icons.shield_outlined,label:'RIESGO'),
            _Feature(icon: Icons.track_changes,label:'CALIBRACIÓN'),
          ]),
          const SizedBox(height: 44),
          LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: BorderRadius.circular(8)),
          const SizedBox(height: 12),
          Text(progress < .72 ? 'INICIANDO MOTORES DE ANÁLISIS…' : 'PREPARANDO MERCADO EN TIEMPO REAL…', style: const TextStyle(fontSize:11, letterSpacing:1.2)),
        ]),
      ))),
    ),
  );
}

class _NexoraMark extends StatelessWidget {
  const _NexoraMark({required this.size}); final double size;
  @override Widget build(BuildContext context) => Container(
    width:size,height:size,
    decoration: BoxDecoration(shape:BoxShape.circle,border:Border.all(color:const Color(0xFF26E6C8),width:3),boxShadow:const [BoxShadow(color:Color(0x5526E6C8),blurRadius:30)]),
    child: CustomPaint(painter:_NPainter()),
  );
}

class _NPainter extends CustomPainter {
  @override void paint(Canvas canvas, Size s) {
    final p=Paint()..style=PaintingStyle.stroke..strokeWidth=s.width*.12..strokeCap=StrokeCap.round..strokeJoin=StrokeJoin.round
      ..shader=const LinearGradient(colors:[Color(0xFF8AF53C),Color(0xFF00D6B2),Color(0xFF16B7FF)]).createShader(Offset.zero & s);
    final path=Path()..moveTo(s.width*.25,s.height*.72)..lineTo(s.width*.42,s.height*.32)..quadraticBezierTo(s.width*.48,s.height*.22,s.width*.56,s.height*.48)..quadraticBezierTo(s.width*.65,s.height*.72,s.width*.78,s.height*.25);
    canvas.drawPath(path,p);
  }
  @override bool shouldRepaint(covariant CustomPainter oldDelegate)=>false;
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon,required this.label}); final IconData icon; final String label;
  @override Widget build(BuildContext context)=>SizedBox(width:72,child:Column(children:[Icon(icon,color:const Color(0xFF55EFA0)),const SizedBox(height:6),Text(label,textAlign:TextAlign.center,style:const TextStyle(fontSize:8,letterSpacing:.7))]));
}
