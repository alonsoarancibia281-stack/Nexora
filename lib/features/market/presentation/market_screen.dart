import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/market_providers.dart';

class MarketScreen extends ConsumerWidget {
  const MarketScreen({super.key});
  @override Widget build(BuildContext context,WidgetRef ref){
    final assets=ref.watch(marketAssetsProvider);final favorites=ref.watch(favoritesProvider).value??{};final query=ref.watch(marketSearchProvider).trim().toUpperCase();
    return Scaffold(appBar:AppBar(title:const Text('Mercado'),actions:[IconButton(onPressed:()=>ref.invalidate(marketAssetsProvider),icon:const Icon(Icons.refresh))]),body:Column(children:[
      Padding(padding:const EdgeInsets.all(16),child:TextField(onChanged:(v)=>ref.read(marketSearchProvider.notifier).state=v,decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Buscar BTC, ETH, SOL…',border:OutlineInputBorder()))),
      Expanded(child:assets.when(loading:()=>const Center(child:CircularProgressIndicator()),error:(e,_)=>Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('No pudimos cargar el mercado.\n$e',textAlign:TextAlign.center))),data:(items){final filtered=items.where((a)=>query.isEmpty||a.symbol.contains(query)||a.baseAsset.contains(query)).take(100).toList();if(filtered.isEmpty)return const Center(child:Text('No encontramos ese activo.'));return RefreshIndicator(onRefresh:()async=>ref.refresh(marketAssetsProvider.future),child:ListView.separated(itemCount:filtered.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,index){final a=filtered[index];final favorite=favorites.contains(a.symbol);return ListTile(onTap:()=>context.go('/market/${a.symbol}'),leading:CircleAvatar(child:Text(a.baseAsset.substring(0,a.baseAsset.length.clamp(0,3)))),title:Text('${a.baseAsset}/${a.quoteAsset}'),subtitle:Text('Volumen 24h: ${_compact(a.volume24h)} USDT'),trailing:SizedBox(width:130,child:Row(mainAxisAlignment:MainAxisAlignment.end,children:[Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,crossAxisAlignment:CrossAxisAlignment.end,children:[Text(_price(a.price),style:const TextStyle(fontWeight:FontWeight.w700)),Text('${a.changePercent24h>=0?'+':''}${a.changePercent24h.toStringAsFixed(2)}%',style:TextStyle(color:a.changePercent24h>=0?Colors.greenAccent:Colors.redAccent))])),IconButton(onPressed:()async{await ref.read(favoritesRepositoryProvider).toggle(a.symbol);ref.invalidate(favoritesProvider);},icon:Icon(favorite?Icons.star:Icons.star_border))]));});})),
    ]));
  }
  String _price(double v)=>v>=1000?v.toStringAsFixed(2):v>=1?v.toStringAsFixed(4):v.toStringAsPrecision(6);
  String _compact(double v)=>v>=1e9?'${(v/1e9).toStringAsFixed(2)}B':v>=1e6?'${(v/1e6).toStringAsFixed(2)}M':v>=1e3?'${(v/1e3).toStringAsFixed(1)}K':v.toStringAsFixed(0);
}
