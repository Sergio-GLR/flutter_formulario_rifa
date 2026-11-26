# Rifa Predial — formulario y servicio interno

Registro de participantes en la Rifa Predial del Municipio de Durango. El
ciudadano captura el número de transacción y la fecha de pago de su recibo
de predial; si el SRM confirma el pago (persona FÍSICA), recibe un boleto.
Solo web.

## Estado (nov 2026)
- **Este repo quedó como referencia.** Nada de la rifa está desplegado. El
  formulario y la API se reescribieron en Astro + Node en el repo
  `Sergio-GLR/formulario_rifa_predial`, que es el que se desarrolla y despliega.
- `servicio_rifa/` (Python) se tradujo a esa API con sus pruebas; no se
  despliega. El Flutter (`lib/`) nunca se publicó.
- Periodo de registro: diciembre 2026 – enero 2027 (sin fecha exacta).

## Arquitectura
Navegador → proxy del servidor (`/api/` → `127.0.0.1:8080`) → `servicio_rifa`
(Flask + waitress) → SRM (`Pr_sorteo`, firma HMAC) y PostgreSQL (función
`registrar_boleto_rifa`, rol `rifa_servicio`). Hasta nov 2026 la base estaba en
Supabase; quedó pausada y se cambió por un PostgreSQL propio.

Reglas que no se negocian:
- El navegador NUNCA conoce token/salt del SRM ni credenciales de la base.
- `/api/registrar` vuelve a consultar el SRM; los datos del predio salen del
  SRM, nunca de la petición.
- `/api/validar` solo devuelve la dirección (nunca propietario ni clave catastral).
- Mismo mensaje si el folio no existe o la fecha no coincide (no revelar folios).
- Al ciudadano solo se le muestran mensajes de la lista permitida
  (`RECHAZOS_DE_LA_BD` en app.py), nunca errores técnicos.
- Sin descarga automática del boleto (equipos compartidos en los módulos).

El esquema y la función `registrar_boleto_rifa` están en
`servicio_rifa/base_datos/esquema.sql`. Reglas de la BD: un boleto por número
de transacción, máximo 5 por teléfono.

## Comandos (PowerShell 5.1: sin `&&`, usar `;`)
Servicio (desde `servicio_rifa/`; necesita red municipal/VPN para hablar con el SRM):
- Pruebas (simuladas, no tocan SRM ni la base): `python -m unittest discover -v tests`
- Pruebas contra Postgres real (Docker): ver `servicio_rifa/README.md`, sección Pruebas
- Local: `python app.py` (con `ORIGENES_PERMITIDOS=http://localhost:5000`, `NUMERO_PROXIES=0` en `.env`)
- Producción: `python servidor.py`
- Diagnóstico manual del SRM (llama al SRM real): `python diagnostico_srm.py [folio]`

Flutter (raíz):
- Pruebas: `flutter test`
- Local: `flutter run -d chrome --web-port 5000 --dart-define=API_BASE=http://localhost:8080`

No correr `app.py`, `servidor.py` ni `diagnostico_srm.py` sin preguntar: usan
el `.env` real.

## Pruebas: convención Falla / Supuesto / Guardia
Las revisiones (`test_revision_*`, `revision_*_test.dart`) nombran sus clases:
- `Falla…`: defecto confirmado; debe pasar.
- `Supuesto…`: algo por confirmar con el SRM/Supabase. **Fallan a propósito**
  hasta que se confirme; no "arreglarlas" sin esa confirmación.
- `Guardia…`: protege contra regresiones.
Estado esperado hoy: Python 83 pruebas / 7 Supuesto en rojo (sin el Postgres de pruebas, las 6 de test_bd_real se saltan); Flutter 50 / 2 en rojo.

## Convenciones
- Código, nombres, comentarios, mensajes y commits en español.
- Comentarios explican el POR QUÉ (casos reales, valores elegidos), no el qué.
- Valores duplicados entre frontend y servicio se marcan en ambos lados
  (ej. `LARGO_MAX_NOMBRE` = `Validadores.largoMaxNombre` = 60).
- Timeouts encadenados: SRM peor caso 26 s + base 13 s = 39 s < 45 s del
  formulario. Si se cambia uno, revisar la suma.
- Commits: una oración en presente que describe el cambio
  ("Limita los fallos por número de transacción, no solo por IP").
- Repo en la cuenta `Sergio-GLR`. Equipo: Sergio, Miguel Almaguer, Aracely.
  Sin revisión de código obligatoria.

## Pendientes conocidos
Los pendientes del proyecto (despliegue, supuestos del SRM, paso a
producción) se llevan en el repo `Sergio-GLR/formulario_rifa_predial`.
