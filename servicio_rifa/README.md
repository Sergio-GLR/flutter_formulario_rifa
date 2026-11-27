# Servicio interno — Rifa Predial

> **Reemplazado (nov 2026).** Este servicio se tradujo a la API en Node del
> repo `Sergio-GLR/formulario_rifa_predial` (`src/servidor/`), con sus mismas
> reglas y pruebas. Se conserva como referencia; **no se despliega**.

Pieza de servidor que verifica cada registro con el SRM antes de guardarlo en
la base de datos (PostgreSQL). Resuelve los hallazgos críticos 1 y 2 de la
revisión de seguridad: el navegador ya no conoce el token ni el salt del SRM
ni ninguna credencial de la base, y nadie puede registrar boletos saltándose
la verificación.

> Hasta nov 2026 la base estaba en Supabase. El proyecto quedó pausado y se
> cambió por un PostgreSQL propio (local y después en el servidor del
> municipio). El esquema está en `base_datos/esquema.sql`.

```
Navegador ──▶ /api/validar, /api/registrar ──▶ SRM (Pr_sorteo)
                         │
                         └──▶ PostgreSQL: registrar_boleto_rifa (rol rifa_servicio)
```

## Qué hace

| Endpoint | Recibe | Devuelve |
| --- | --- | --- |
| `POST /api/validar` | `txca`, `fecha_pago` (AAAA-MM-DD) | `{"ok": true, "direccion": "..."}` |
| `POST /api/registrar` | `txca`, `fecha_pago`, `nombre`, `apellido_paterno`, `apellido_materno` (opcional), `telefono` | `{"ok": true, "mensaje": "...", "boleto": {"txca", "nombre"}}` |
| `GET /api/salud` | — | `{"ok": true}` |

Los errores responden `{"ok": false, "mensaje": "<texto para el ciudadano>"}` con
HTTP 400 (datos inválidos), 422 (rechazo), 429 (demasiados intentos) o 503
(SRM o base de datos sin respuesta). El formulario solo tiene que mostrar `mensaje`.

Reglas que aplica:

- **La fecha de pago debe coincidir** con la del SRM. Si no coincide, o si el folio
  no existe, el mensaje es el mismo: así nadie puede averiguar qué folios existen.
- **Solo personas FÍSICAS.**
- **Los datos del predio salen del SRM**, nunca de la petición del navegador.
- `/api/registrar` **vuelve a consultar el SRM**: no confía en que el navegador ya validó.
- `/api/validar` devuelve **solo la dirección**, nunca el propietario ni la clave catastral.
- **Límite de intentos por IP** (15 cada 10 minutos por defecto). Las redes de los
  módulos del municipio quedan exentas.
- **Límite de fallos por folio** (5 por hora por defecto), sin importar la IP:
  sin él, con una IP distinta por intento se prueban todas las fechas de pago de un
  folio ajeno. Al llegar al límite ni la fecha correcta pasa; el ciudadano debe
  esperar o ir a un módulo (las redes internas también quedan exentas aquí).

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
   El tiempo de espera del proxy debe ser de **al menos 45 s** (lo que espera
   el formulario; el servicio tarda 39 s en el peor caso). Los valores por
   defecto de Nginx (60 s) e IIS/ARR (120 s) ya alcanzan.

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

## Base de datos

`base_datos/esquema.sql` crea, en una base PostgreSQL 17+ vacía, las tablas
`Pagadores`, `Predios` y `Boletos_Rifa` y las funciones
`registrar_boleto_rifa`, `normalizar_telefono` y `obtener_boletos_impresion`
(copiadas del backup de Supabase del 19 oct 2026). También crea el rol
`rifa_servicio`, que **solo** puede ejecutar `registrar_boleto_rifa`: no lee
ni escribe las tablas directamente.

Instalarla (como dueño de la base):

```
createdb rifa_predial
psql -d rifa_predial -v ON_ERROR_STOP=1 -f base_datos/esquema.sql
psql -d rifa_predial -c "ALTER ROLE rifa_servicio LOGIN PASSWORD '...'"
```

y poner en `.env` `DATABASE_URL=postgresql://rifa_servicio:...@HOST:5432/rifa_predial`.
La contraseña nunca va en Git.

Reglas que aplica la función: un boleto por número de transacción y máximo 5
por teléfono (normalizado: sin espacios, guiones ni +52). Si cambian sus
mensajes de rechazo, hay que cambiar `RECHAZOS_DE_LA_BD` en `app.py`
(`tests/test_bd_real.py` lo revisa).

## Pruebas

Con el SRM y la base simulados (no tocan nada externo):

```
python -m unittest discover -v tests
```

Las pruebas `Supuesto…` fallan a propósito hasta confirmar con el SRM cada
supuesto (ver el encabezado de cada archivo `test_revision_*`).

Contra un PostgreSQL real, con un contenedor de Docker solo para pruebas
(credenciales de prueba en `base_datos/compose.pruebas.yaml`):

```
docker compose -f base_datos/compose.pruebas.yaml up -d
$env:PRUEBAS_BD_ADMIN = "postgresql://postgres:pruebas_admin@127.0.0.1:55432/rifa_predial"
$env:PRUEBAS_BD_URL   = "postgresql://rifa_servicio:pruebas_rifa@127.0.0.1:55432/rifa_predial"
python -m unittest -v tests.test_bd_real
docker compose -f base_datos/compose.pruebas.yaml down -v
```

Sin esas variables, `tests.test_bd_real` se salta. Nunca apuntarlas a la base
del servidor: cada prueba borra las tablas.

## Pasar a PostgreSQL en el servidor

1. Instalar PostgreSQL 17 o superior y crear la base con `base_datos/esquema.sql`
   (sección anterior).
2. `python -m pip install -r requirements.txt` (agrega `psycopg`).
3. En el `.env` del servidor: agregar `DATABASE_URL` y borrar `SUPABASE_URL` y
   `SUPABASE_SECRET_KEY`.
4. Reiniciar el servicio y probar un registro.
