import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/validators.dart';
import '../data/auth_repository.dart';

class RegisterScreen extends StatefulWidget { const RegisterScreen({super.key}); @override State<RegisterScreen> createState()=>_RegisterScreenState(); }
class _RegisterScreenState extends State<RegisterScreen> {
 final form=GlobalKey<FormState>(); final first=TextEditingController(),last=TextEditingController(),email=TextEditingController(),pass=TextEditingController(),confirm=TextEditingController(),country=TextEditingController();
 String experience='Principiante'; bool terms=false,privacy=false,marketing=false,loading=false; String? error;
 Future<void> submit() async { if(!form.currentState!.validate())return; if(pass.text!=confirm.text){setState(()=>error='Las contraseñas no coinciden');return;} if(!terms||!privacy){setState(()=>error='Debes aceptar los términos y la política de privacidad');return;} setState((){loading=true;error=null;}); try{await AuthRepository(Supabase.instance.client).register(email:email.text,password:pass.text,firstName:first.text,lastName:last.text,country:country.text,experience:experience,marketing:marketing); if(mounted)context.go('/verify?email=${Uri.encodeComponent(email.text.trim())}');} on AuthException catch(e){setState(()=>error=e.message);} catch(_){setState(()=>error='No pudimos completar el registro.');} finally{if(mounted)setState(()=>loading=false);} }
 @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Crear cuenta')),body:SafeArea(child:ListView(padding:const EdgeInsets.all(24),children:[Form(key:form,child:Column(children:[
 TextFormField(controller:first,validator:Validators.required,decoration:const InputDecoration(labelText:'Nombre')),TextFormField(controller:last,validator:Validators.required,decoration:const InputDecoration(labelText:'Apellido')),TextFormField(controller:email,validator:Validators.email,keyboardType:TextInputType.emailAddress,decoration:const InputDecoration(labelText:'Correo electrónico')),TextFormField(controller:country,validator:Validators.required,decoration:const InputDecoration(labelText:'País')),
 DropdownButtonFormField<String>(value:experience,items:['Principiante','Intermedio','Avanzado'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(v)=>setState(()=>experience=v!),decoration:const InputDecoration(labelText:'Nivel de experiencia')),
 TextFormField(controller:pass,validator:Validators.password,obscureText:true,decoration:const InputDecoration(labelText:'Contraseña')),TextFormField(controller:confirm,obscureText:true,decoration:const InputDecoration(labelText:'Confirmar contraseña')),
 CheckboxListTile(value:terms,onChanged:(v)=>setState(()=>terms=v??false),title:const Text('Acepto los Términos y Condiciones')),CheckboxListTile(value:privacy,onChanged:(v)=>setState(()=>privacy=v??false),title:const Text('Acepto la Política de Privacidad')),CheckboxListTile(value:marketing,onChanged:(v)=>setState(()=>marketing=v??false),title:const Text('Deseo recibir novedades y promociones')),
 const Padding(padding:EdgeInsets.symmetric(vertical:12),child:Text('Los análisis son probabilísticos. Las criptomonedas son volátiles y puedes perder parte o todo tu capital. Nexora no sustituye asesoría financiera profesional.')),
 if(error!=null)Text(error!),const SizedBox(height:12),SizedBox(width:double.infinity,child:FilledButton(onPressed:loading?null:submit,child:Text(loading?'Creando…':'Crear cuenta')))
 ]))])));
}
