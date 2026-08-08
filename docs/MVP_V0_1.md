# Nexora Markets AI — MVP v0.1

## Objetivo

Publicar y probar una primera versión útil de Nexora sin fricción de entrada.

## Decisión de producto

La v0.1 funciona en **modo invitado**:

- Sin registro ni inicio de sesión.
- Sin verificación por correo.
- Sin planes de suscripción ni pagos.
- Sin publicidad en esta primera prueba.
- Sin custodia de dinero, depósitos, retiros ni ejecución de operaciones.
- Sin panel administrativo expuesto desde la app.

La infraestructura de autenticación, roles, planes y Owner desarrollada previamente se conserva en el repositorio y en Supabase para una versión posterior, pero no forma parte del flujo de navegación de la v0.1.

## Alcance funcional prioritario

1. Inicio / resumen del mercado.
2. Buscador de criptomonedas.
3. Precio y variación en tiempo real.
4. Gráfico de velas.
5. Temporalidades 5m, 15m, 1h, 4h, 1d y 1w.
6. RSI, MACD, EMA 9/21/50/200, Bollinger, ATR, ADX, estocástico y volumen.
7. Tendencia y puntuación Nexora de -100 a +100.
8. Semáforo de riesgo y confianza del análisis.
9. Soportes, resistencias y condiciones de invalidación.
10. Calculadora de gestión de riesgo.
11. Explicaciones educativas de los indicadores.

## Datos

La app puede consumir endpoints públicos de Binance para datos de mercado. No se solicitarán API keys privadas del usuario y Nexora no ejecutará operaciones.

Si la API no está disponible, la interfaz debe mostrar estados de error claros y podrá usar datos simulados únicamente cuando estén identificados explícitamente como demostración.

## Monetización posterior

Free, Essential, Pro Trader y Elite AI quedan fuera del MVP. Se reactivarán después de validar estabilidad, utilidad y experiencia de usuario. Ningún componente del MVP debe bloquear funciones solicitando un pago.

## Seguridad

Aunque el MVP no exige cuentas, no se deben exponer service-role keys, secretos de Supabase ni credenciales privadas en Flutter. Solo pueden incluirse identificadores o claves públicas diseñadas para clientes.
