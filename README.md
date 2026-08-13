# Nexora Markets AI

Aplicación móvil profesional de análisis educativo y probabilístico de mercados de criptomonedas.

> Nexora Markets AI no custodia fondos, no ejecuta operaciones y no garantiza resultados financieros.

## Fase 1

La rama de Fase 1 implementa la base de identidad y seguridad: Flutter + Riverpod + GoRouter, Supabase Auth/PostgreSQL, registro, verificación OTP de seis dígitos, recuperación de contraseña, consentimientos, roles, planes, entitlements, sesiones/dispositivos y acceso Owner validado exclusivamente en servidor.

También incluye un panel administrativo base para Owner con métricas, búsqueda de usuarios, cambio de plan, suspensión/reactivación, feature flags y auditoría. El Owner está protegido contra degradación o suspensión por las operaciones administrativas normales.

La verificación de correo usa OTP generado criptográficamente en Edge Functions, hash + pepper, expiración, un solo uso, bloqueo por intentos, rate limiting por correo/IP, respuestas anti-enumeración y lookup interno restringido a `service_role`.

## Configuración Flutter

Usa variables de compilación públicas, no archivos `.env` empaquetados:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLIC_KEY \
  --dart-define=PASSWORD_RECOVERY_REDIRECT=nexora://update-password
```

Los secretos (`OWNER_EMAIL`, `OTP_PEPPER`, `RESEND_API_KEY`, `EMAIL_FROM`, `APP_ORIGIN`) deben configurarse únicamente en Supabase/Edge Functions.

Consulta `docs/PHASE_1.md` y `docs/PHASE_1_CHECKLIST.md` para instalación, seguridad y pendientes de staging.

## Predicciones minutos BTC

El apartado de predicciones funciona como una sala de análisis de **401 agentes** que trabajan sobre rondas de cinco minutos sincronizadas con el reloj de Binance.

| Consejo | Agentes | Qué aporta |
| --- | --- | --- |
| Analistas de mercado | 100 | Diez equipos (momentum, tendencia, volatilidad, reversión, libro, flujo, volumen, price action, intermercado, régimen) con genoma evolutivo |
| Matemáticos | 50 | Diez ramas y cincuenta operaciones complejas (Ornstein-Uhlenbeck, Hurst, DFT, entropías, Kalman, GARCH, Lyapunov, valores extremos, PCA/SSA, control óptimo) |
| Patrones históricos | 100 | Diez lentes buscando episodios análogos en años de velas de 5m, 1h, 4h y 1d |
| Noticias en vivo | 50 | Diez mesas leyendo feeds públicos de Bitcoin cada 45 segundos |
| Auditoría | 100 | Test final en diez dominios sobre todo lo anterior antes de elevar el paquete |
| Analista jefe | 1 | Escucha durante el primer minuto de la ronda y fija una única decisión: sube o baja al cierre |

### Cómo funciona una ronda

1. **Apertura.** El stream de klines de Binance entrega el instante exacto de inicio, la apertura de la vela y el contador. Se procesa el gráfico y se fija la tesis de la ronda con objetivo y nivel de invalidación.
2. **Minuto de decisión.** Los consejos entregan lecturas cada tres segundos. La auditoría recorta la evidencia según lo que encuentra y el analista jefe bloquea el veredicto al cumplirse el primer minuto.
3. **Seguimiento.** El gráfico en vivo, el avance hacia el objetivo y el estado de la tesis se actualizan con cada tick hasta el cierre.
4. **Aprendizaje.** Al cerrar la vela se comparan apertura y cierre: los analistas que acertaron ganan peso, los que fallaron lo pierden y, cada cierto nivel de experiencia, los peores se reemplazan por cruces mutados de los mejores. El estado evolutivo se guarda en el dispositivo.

La pestaña **Red neuronal** muestra en vivo el flujo completo —datos, consejos, equipos, auditoría y analista jefe— con el color indicando dirección y el grosor la fuerza de la evidencia.

### Sobre la app de Binance

La sección de predicciones puede quedarse flotando encima de cualquier otra app —la de Binance en particular— con el veredicto expresado como orden (**COMPRAR** / **VENDER** / **ESPERAR**), la probabilidad y la cuenta atrás de la vela. El panel se arrastra a donde estorbe menos y, al tocarlo, devuelve a Nexora. Android exige el permiso «mostrar sobre otras apps», que se concede desde sus ajustes; Nexora arranca la superposición sola al volver.

No lee la pantalla que hay debajo: el análisis sale del mismo feed de mercado de Binance que la app ya recibe.

Desde ahí se puede **vigilar una operación**. Si abres la compra o la venta en el exchange y pulsas *proteger*, Nexora observa el nivel de invalidación de esa ronda y avisa en el acto —panel en rojo, vibración y notificación— cuando el precio lo rompe, cuando el consejo se da la vuelta o cuando la vela se acaba. **Nexora no ejecuta ni cancela órdenes**: no tiene claves de tu cuenta. Vigila y avisa; abrir y cerrar lo haces tú.

El código nativo de Android vive en `android_native/` y `tool/android_wrapper.py` lo integra en el envoltorio que el CI genera con `flutter create`.

### Validación

El motor se mide con `tool/backtest.dart`, que replica la historia real de Binance ronda a ronda: al minuto uno corre el consejo completo con los datos disponibles en ese instante, emite la llamada y recién después la puntúa contra el cierre. La población aprende tras cada ronda, así que la medición es fuera de muestra.

Última corrida: **10.999 rondas** entre el 6 de julio y el 13 de agosto de 2026.

| Métrica | Valor |
| --- | --- |
| Acierto con lectura (54% de las rondas) | **69,20%** |
| Acierto sobre todas las rondas | 64,13% |
| Rondas silenciadas por la puerta | 46% (habrían acertado 58,18%) |
| Calibración | 20‑30% → subió 22,2% · 50‑60% → 57,6% · 70‑80% → 79,3% |

El resultado se sostiene en los tres terciles de volatilidad (69,2% / 67,8% / 70,7% con lectura) y en los seis tramos cronológicos (67,4% a 70,6%), así que no es un artefacto de una semana concreta.

**Qué produce ese acierto.** Al minuto uno ya se conoce un quinto de la vela. Bajo difusión, el cierre queda por encima de la apertura con probabilidad Φ(d/σ√τ), y seguir sólo esa cantidad acierta el 64,41% —frente al 50,84% de la clase mayoritaria—. El motor completo rinde 64,13%: estadísticamente indistinguible de esa referencia (z = −0,30).

Dicho sin adornos: **el mérito medible es del ancla de difusión y de la puerta de seguridad, no de los 401 agentes.** Los consejos ya no restan —antes de anclarlos perdían casi cinco puntos contra la referencia— pero tampoco suman de forma detectable en klines.

### El flujo de órdenes

`tool/flow_information.dart` reconstruye el tape real desde los volcados diarios de Binance y pregunta lo que el A/B extremo a extremo no podía separar: ¿queda información en la microestructura una vez descontada el ancla? Sobre 8.639 rondas de treinta días, tres features pasan el umbral de Bonferroni —desequilibrio agresor (z = 5,06), impulso de precio (z = 3,39) y persistencia (z = 3,55)— y las cinco de vela salen nulas, porque el ancla ya las absorbe. La prueba conjunta da χ² = 49,09 con 5 g.l. contra un crítico de 11,07.

Ese ajuste se copió al consenso tal cual: el tape entra una vez, con sus coeficientes, y el ancla entra encogida por el suyo. Sobre las 2.592 rondas apartadas del ajuste, la log‑pérdida baja de 0,64068 a 0,63400 y el acierto de 63,19% a 64,58%.

Medido de punta a punta sobre las mismas 2.879 rondas, con y sin ese término:

| | sin flujo | con flujo |
| --- | --- | --- |
| Acierto | 63,63% | 63,84% |
| Brier | 0,23024 | **0,22704** |
| Cobertura de la puerta | 44,2% | **50,9%** |
| Acierto con lectura | 69,52% | 69,74% |

Lo que compra el flujo no es acierto bruto —dos décimas, ruido— sino **confianza mejor medida**: con el mismo umbral del 6% el motor se atreve a hablar en la mitad de las rondas en vez de en el 44%, y acierta igual. Ese tramo del backtest cae dentro de la ventana donde se ajustaron los coeficientes; el número limpio es el de la validación apartada.

Lo que sigue sin resolverse: el motor empata con la regla del primer minuto (−0,10 puntos, z = −0,06) y cuando la contradice acierta el 49,51%. Mejor que el 40,72% del que se partía, pero todavía no es aportar. El `random_walk_guard` y el `cost_benchmark` del marco de conocimiento de Nexora siguen dando los 401 agentes por no probados.

> Modelo experimental de uso educativo: no ejecuta operaciones ni garantiza resultados.
