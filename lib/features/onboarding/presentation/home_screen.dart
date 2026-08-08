import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Nexora Markets AI'),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                  child: const Text('MVP · Acceso libre'),
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(child:ListView(padding:const EdgeInsets.all(20),children:[
          const Text('Entiende el mercado antes de actuar',style:TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
          const SizedBox(height:8),
          const Text('Precios reales, velas y datos públicos de mercado sin registro, pagos ni custodia de fondos.'),
          const SizedBox(height:24),
          _InfoCard(icon:Icons.show_chart,title:'Mercado en tiempo real',description:'Consulta pares USDT, variación 24 h, volumen, favoritos y velas.',onTap:()=>context.go('/market')),
          const _InfoCard(icon:Icons.analytics_outlined,title:'Analizar',description:'Indicadores técnicos, tendencia, riesgo y escenarios llegarán en la Fase 3.'),
          const _InfoCard(icon:Icons.calculate_outlined,title:'Gestión de riesgo',description:'Calcula tamaño de posición, pérdida máxima y relación riesgo-beneficio.'),
          const SizedBox(height:16),
          Card(child:Padding(padding:const EdgeInsets.all(18),child:Text('Nexora es una herramienta educativa y de análisis probabilístico. No garantiza ganancias ni sustituye asesoría financiera profesional.',style:TextStyle(color:Theme.of(context).colorScheme.onSurfaceVariant)))),
        ])),
      );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon,required this.title,required this.description,this.onTap});
  final IconData icon;final String title,description;final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Card(margin:const EdgeInsets.only(bottom:12),child:ListTile(onTap:onTap,contentPadding:const EdgeInsets.all(16),leading:Icon(icon,size:30),title:Text(title,style:const TextStyle(fontWeight:FontWeight.w700)),subtitle:Padding(padding:const EdgeInsets.only(top:6),child:Text(description)),trailing:onTap==null?null:const Icon(Icons.chevron_right)));
}
