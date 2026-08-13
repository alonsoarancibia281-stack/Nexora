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

El motor se mide con `tool/backtest.dart`, que replica la historia real de Binance ronda a ronda: al minuto uno corre el consejo completo con los datos disponibles en ese instante, emite la llamada y sólo después la puntúa contra el cierre. La población aprende tras cada ronda, así que ninguna predicción ha visto su propio resultado.

**El rival correcto no es la moneda.** Al minuto uno ya ocurrió un quinto de la vela, y seguir sólo esa parte ya realizada acierta alrededor del 64% —cerca del techo mecánico ½ + arcsin√(t/T)/π = 64,76%—. Batir al 50% no significa nada; todo lo que sigue se compara contra esa regla trivial.

### El flujo de órdenes

`tool/flow_information.dart` reconstruye el tape real desde los volcados diarios de Binance y pregunta lo que el A/B extremo a extremo no podía separar: ¿queda información en la microestructura una vez descontada el ancla? Sobre 8.639 rondas de treinta días, tres features pasan el umbral de Bonferroni —desequilibrio agresor, impulso de precio y persistencia— y las cinco de vela salen nulas, porque el ancla ya las absorbe.

Ese ajuste se copia al consenso tal cual: el tape entra una sola vez, con sus coeficientes, en vez de diluirse entre cien votos y quedar truncado por el límite del consejo.

Una cautela sobre las ventanas: el desequilibrio y el impulso a 30, 60 y 120 segundos pasan el umbral **por separado**, pero metidos juntos en el mismo ajuste se canibalizan —el de 30 s llega a cambiar de signo— y el modelo empeora fuera de muestra (63,70% contra 64,74%). Pasar la prueba en solitario no es merecer asiento en el ajuste conjunto. Se quedan las tres lecturas de la ventana de 60 s.

### La σ del ancla

El ancla es Φ(d/σ√τ). Durante meses su coeficiente ajustado salía 0,7754 ± 0,0266 y se leía como «el ancla exagera». Era otra cosa: σ venía del ATR de 14 periodos multiplicado por un 0,72 puesto a mano, y el ATR es rango verdadero, no desviación típica de retornos —su razón se ensancha en tendencia y se estrecha en lateral, así que la z entraba sesgada—.

`tool/anchor_lab.dart` compara cinco estimadores sobre las mismas 8.639 rondas:

| σ | coeficiente | ± | log‑pérdida |
| --- | --- | --- | --- |
| ATR × 0,72 (lo que había) | 0,7754 | 0,0266 | 0,64068 |
| Desviación típica de 60 m | 0,9569 | 0,0331 | 0,63530 |
| Bipotencia | 0,8180 | 0,0287 | 0,63457 |
| **EWMA de retornos de 1 m** | **0,9943** | 0,0336 | 0,63458 |
| EWMA con forma horaria | 0,9095 | 0,0315 | 0,63357 |

Un coeficiente de 1,00 significa que la probabilidad se puede tomar al pie de la letra. La EWMA de retornos de un minuto da 0,9943 ± 0,0336. **La difusión nunca fue el modelo equivocado; σ estaba mal estimada.**

Se envía la EWMA. La variante estacional gana 0,001 de log‑pérdida, que no compensa veinticuatro constantes ajustadas que además no se pueden estimar en el móvil, y encima su coeficiente se aleja de 1; queda medida en el banco.

### Lo que fue moviendo la aguja

Todas las filas son la misma ventana de 2.879 rondas (3–12 de agosto), decidiendo al minuto uno. La referencia a batir es la regla trivial de seguir el primer minuto, que en esa ventana acierta el 63,95%.

| versión | acierto | ventaja | al contradecir | Brier | puerta 6% |
| --- | --- | --- | --- | --- | --- |
| consejos sin anclar | 59,18% | −4,90 | 40,72% | — | — |
| ancla de difusión (ATR) | 63,63% | −0,31 | 48,65% | 0,23024 | 44,2% → 69,52% |
| + flujo de órdenes | 63,84% | −0,10 | 49,51% | 0,22704 | 50,9% → 69,74% |
| + σ de EWMA | 63,88% | −0,07 | 49,69% | 0,22726 | 50,2% → 69,92% |
| + reparto reajustado | **64,40%** | **+0,45** | **52,38%** | **0,22564** | **52,4% → 70,62%** |

Dos lecturas honestas de esa última fila. Es la primera vez que el motor queda **por encima** de la regla trivial en vez de por debajo, y la primera vez que acierta más de la mitad de las veces que la contradice —que es la fila donde se ve si aporta o destruye información—. Pero +0,45 puntos con z = 0,24 **no es significativo**: sigue siendo un empate, sólo que ya no un empate perdiendo. Y esa ventana solapa con los treinta días donde se ajustaron los coeficientes; el número limpio es el de la validación apartada, 64,66% con log‑pérdida 0,63246 frente a 63,19% y 0,63458 del ancla sola.

El resultado aguanta en los tres terciles de volatilidad (63,5% / 64,2% / 65,5%) y en los cinco tramos cronológicos (63,1% a 66,5%), así que no es una semana con suerte.

**De dónde sale el acierto.** Al minuto uno ya se conoce un quinto de la vela. Bajo difusión, el cierre queda por encima de la apertura con probabilidad Φ(d/σ√τ), y seguir sólo esa cantidad acierta el 63,95% frente al 52,14% de la clase mayoritaria. El mérito medible sigue siendo del ancla, del tape y de la puerta de seguridad. Los 401 agentes ya no restan —antes de anclarlos perdían casi cinco puntos— pero su aporte propio sigue sin ser detectable, y el `random_walk_guard` y el `cost_benchmark` del marco de conocimiento de Nexora los siguen dando por no probados.

> Modelo experimental de uso educativo: no ejecuta operaciones ni garantiza resultados.
