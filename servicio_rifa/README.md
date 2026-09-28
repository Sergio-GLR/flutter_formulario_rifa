# Servicio interno — Rifa Predial

Pieza de servidor que verifica cada registro con el SRM antes de guardarlo en
Supabase. Resuelve los hallazgos críticos 1 y 2 de la revisión de seguridad:
el navegador ya no conoce el token ni el salt del SRM ni ninguna clave de
Supabase, y nadie puede registrar boletos saltándose la verificación.

```
Navegador ──▶ /api/validar, /api/registrar ──▶ SRM (Pr_sorteo)
                         │
                         └──▶ Supabase: registrar_boleto_rifa (clave secreta)
```

## Qué hace

| Endpoint | Recibe | Devuelve |
| --- | --- | --- |
| `POST /api/validar` | `txca`, `fecha_pago` (AAAA-MM-DD) | `{"ok": true, "direccion": "..."}` |
| `POST /api/registrar` | `txca`, `fecha_pago`, `nombre`, `apellido_paterno`, `apellido_materno` (opcional), `telefono` | `{"ok": true, "mensaje": "...", "boleto": {"txca", "nombre"}}` |
| `GET /api/salud` | — | `{"ok": true}` |

Los errores responden `{"ok": false, "mensaje": "<texto para el ciudadano>"}` con
HTTP 400 (datos inválidos), 422 (rechazo), 429 (demasiados intentos) o 503
(SRM o Supabase sin respuesta). El formulario solo tiene que mostrar `mensaje`.

Reglas que aplica:

- **La fecha de pago debe coincidir** con la del SRM. Si no coincide, o si el folio
  no existe, el mensaje es el mismo: así nadie puede averiguar qué folios existen.
- **Solo personas FÍSICAS.**
- **Los datos del predio salen del SRM**, nunca de la petición del navegador.
- `/api/registrar` **vuelve a consultar el SRM**: no confía en que el navegador ya validó.
- `/api/validar` devuelve **solo la dirección**, nunca el propietario ni la clave catastral.
- **Límite de intentos por IP** (15 cada 10 minutos por defecto). Las redes de los
  módulos del municipio quedan exentas.

## Instalar en el servidor municipal

1. Python 3.10 o superior. En la carpeta del servicio:
   ```
   python -m pip install -r requirements.txt
   ```
2. Copiar `.env.example` como `.env` y llenar los valores. Usar la URL de TEST
   del SRM hasta cerrar pruebas.
3. Arrancar:
   ```
   python servidor.py
   ```
   Escucha solo en `127.0.0.1:8080`. Conviene registrarlo como servicio de
   Windows (por ejemplo con NSSM) para que arranque solo.
4. En el servidor web que ya publica el formulario (IIS, Nginx o Apache),
   agregar una regla de proxy inverso: `/api/` → `http://127.0.0.1:8080/api/`.
   Así el formulario y el servicio comparten dominio y no hace falta CORS.

### Dos valores que hay que confirmar con quien administra el servidor

- `NUMERO_PROXIES`: cuántos proxies hay delante del servicio (normalmente 1).
  Si queda en 0 detrás de un proxy, todas las peticiones parecen venir de la
  misma IP y el límite de intentos bloquearía a todos a la vez.
- `REDES_INTERNAS`: los rangos de IP de los módulos, para que no se les
  aplique el límite.

## Probar en tu computadora (formulario + servicio)

Necesitas estar en la red municipal (o VPN), porque el servicio consulta el SRM.

1. En `servicio_rifa\.env` agrega `ORIGENES_PERMITIDOS=http://localhost:5000`
   y `NUMERO_PROXIES=0`, y arranca el servicio:
   ```
   python app.py
   ```
2. En `flutter_formulario_rifa`:
   ```
   flutter run -d chrome --web-port 5000 --dart-define=API_BASE=http://localhost:8080
   ```

En producción no hace falta nada de esto: la app y el servicio comparten
dominio y la app llama a `/api/...` directamente.

## Pruebas

```
python -m unittest -v tests.test_servicio
```

29 pruebas con el SRM y Supabase simulados. Cubren la verificación, la fecha
de pago, la persona FÍSICA, la privacidad de las respuestas, la validación de
entradas, el límite de intentos y el cliente del SRM (firma, reintentos,
respuestas inesperadas). La firma HMAC se verificó contra el ejemplo de la
sección 6 de la documentación del SRM.

## Después de instalarlo

1. Cambiar el formulario para que llame a `/api/validar` y `/api/registrar`,
   y agregar el campo de fecha de pago.
2. Quitar `.env` de los assets de `pubspec.yaml` y borrar de la app el token,
   el salt y las claves de Supabase.
3. En Supabase: `revoke execute on function registrar_boleto_rifa(...) from anon, authenticated;`
4. Correr los tests del formulario (`flutter test test/revision_test.dart`) y de la
   base (`tests.test_bd_real` en `script_boletos`): todos deben quedar en verde.
