"""
Cuarta revisión: intentar romper el servicio (1 oct 2026).

Se buscaron regresiones, errores de lógica, problemas de seguridad y
supuestos en lo que quedó después de la revisión adversarial. NO se corrigió
nada: estas pruebas FALLAN con el código actual y deben pasar cuando se
corrija cada defecto (o borrarse si se confirma que el supuesto es cierto).
Correr desde la carpeta servicio_rifa:

    python -m unittest -v tests.test_revision_cuarta_ronda

Convención (igual que en las rondas anteriores):
  * clase Falla...    -> defecto confirmado.
  * clase Supuesto... -> el código asume algo que no está garantizado; hay que
                         confirmarlo con el SRM / Supabase antes de decidir.
  * clase Guardia...  -> pasa hoy; protege lo que una corrección podría romper.
"""

import copy
import logging
import os
import socket
import sys
import threading
import time
import unittest
from unittest import mock

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import srm as modulo_srm  # noqa: E402
from bd import BDNoDisponible, ClienteSupabase  # noqa: E402
from limites import LimiteIntentos  # noqa: E402
from srm import ClienteSRM, TransaccionRechazada  # noqa: E402

from tests.test_servicio import (  # noqa: E402
    OK_SRM, SALT_FALSO, TOKEN_FALSO, _Base, _Resp, _SesionFalla,
    datos_registro, predio)

MSG_YA_REGISTRADO = "Este número de transacción ya fue registrado anteriormente."


def setUpModule():
    logging.disable(logging.CRITICAL)


def tearDownModule():
    logging.disable(logging.NOTSET)


def srm_con_respuesta(datos):
    return ClienteSRM("https://srm", TOKEN_FALSO, SALT_FALSO,
                      sesion=_SesionFalla(_Resp(datos)))


class BDConUnicidad:
    """Como registrar_boleto_rifa: un número de transacción solo una vez."""

    def __init__(self):
        self.registrados = {}

    def registrar_boleto(self, **kw):
        if kw["txca"] in self.registrados:
            return {"success": False, "message": MSG_YA_REGISTRADO}
        self.registrados[kw["txca"]] = kw
        return {"success": True, "message": "Registro completado exitosamente."}


# ============================================ srm.py: datos del predio vacíos
class FallaDatosDelPredioVacios(_Base):
    """srm.py exige que una persona FÍSICA traiga cc, propietario y domicilio,
    pero solo revisa que no sean None (test_fisica_sin_datos_del_predio_no_se_registra
    solo prueba None). Si el SRM manda "" o "   ", `texto()` devuelve "" y el
    boleto se guarda sin clave catastral, sin propietario o sin dirección; y
    /api/validar le pide al ciudadano confirmar una dirección en blanco."""

    def test_fisica_con_datos_vacios_no_se_registra(self):
        for campo in ("cc", "propietario", "domicilio"):
            for vacio in ("", "   "):
                with self.subTest(campo=campo, valor=repr(vacio)):
                    datos = copy.deepcopy(OK_SRM)
                    datos["response"][campo] = vacio
                    self.armar(srm=srm_con_respuesta(datos))
                    r = self.post("/api/registrar", datos_registro())
                    self.assertNotEqual(r.status_code, 200)
                    self.assertEqual(self.bd.llamadas, [])

    def test_validar_no_pide_confirmar_una_direccion_vacia(self):
        datos = copy.deepcopy(OK_SRM)
        datos["response"]["domicilio"] = ""
        self.armar(srm=srm_con_respuesta(datos))
        r = self.post("/api/validar", {"txca": "2026-337308", "fecha_pago": "2026-09-03"})
        self.assertNotEqual(r.status_code, 200)


# ======================================= srm.py: "error": null en un éxito
class SupuestoElExitoNoTraeLaLlaveError(unittest.TestCase):
    """srm.py decide que es un rechazo con `"error" in datos`, aunque valga
    null. Muchos servicios responden siempre las dos llaves:
    {"response": {...}, "error": null}. Si el SRM lo hace, TODOS los pagos
    válidos se rechazan con "No encontramos un pago de predial vigente" (422,
    log en INFO, nadie se entera).

    Además diagnostico_srm.py revisa "response" PRIMERO: en ese caso el
    diagnóstico diría "✅ transacción válida" mientras el servicio rechaza a
    todos. Confirmar con el SRM qué manda en un éxito."""

    def test_error_nulo_con_response_valida_es_exito(self):
        datos = copy.deepcopy(OK_SRM)
        datos["error"] = None
        try:
            p = srm_con_respuesta(datos).consultar("2026-337308")
        except TransaccionRechazada as e:
            self.fail(f"Un pago válido se trató como rechazo: {e}")
        self.assertEqual(p.domicilio, "CALLE 1")

    def test_error_nulo_sin_response_no_es_rechazo_de_negocio(self):
        """{"error": null} solo no dice qué pasó: no es "tu folio no existe"."""
        try:
            srm_con_respuesta({"error": None}).consultar("2026-337308")
        except modulo_srm.SRMNoDisponible:
            return
        except TransaccionRechazada as e:
            self.fail(f"Se le diría al ciudadano que su folio no existe: {e}")
        self.fail("No lanzó ninguna excepción")


# ============================== srm.py / bd.py: el timeout no es por petición
class _ServidorGoteo:
    """Servidor HTTP local que contesta un byte cada `pausa` segundos. Nunca
    se queda callado más que `pausa`, así que el timeout de lectura de
    requests (que es entre bytes, no total) nunca se dispara."""

    def __init__(self, cuerpo, pausa):
        self.cuerpo, self.pausa = cuerpo, pausa
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(4)
        self.url = f"http://127.0.0.1:{self.sock.getsockname()[1]}/"
        threading.Thread(target=self._servir, daemon=True).start()

    def _servir(self):
        while True:
            try:
                con, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._atender, args=(con,), daemon=True).start()

    def _atender(self, con):
        try:
            con.recv(65536)
            con.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                        b"Content-Length: " + str(len(self.cuerpo)).encode() + b"\r\n\r\n")
            for i in range(len(self.cuerpo)):
                con.sendall(self.cuerpo[i:i + 1])
                time.sleep(self.pausa)
        except OSError:
            pass
        finally:
            con.close()

    def cerrar(self):
        self.sock.close()


def _sesion_sin_proxy():
    s = requests.Session()
    s.trust_env = False  # que no pase por el proxy del entorno
    return s


class SupuestoElTimeoutLimitaLaPeticionCompleta(unittest.TestCase):
    """srm.py y bd.py calculan el peor caso como conectar + leer (39 s, menos
    que los 45 s del formulario). Pero en requests el timeout de LECTURA es
    el máximo entre dos bytes, no el total de la respuesta: un SRM o un
    Supabase lento que va soltando la respuesta poco a poco (un proxy
    saturado, una red mala) mantiene la petición viva sin límite. El
    formulario se rinde, el servicio sí registra y al reintentar el ciudadano
    recibe "ya fue registrado" y nunca ve su boleto.

    test_el_peor_caso_del_servicio_cabe_en_la_espera_del_formulario solo suma
    los números de las tuplas; aquí se mide el tiempo real con escalas
    pequeñas: timeouts (0.5, 1.0) y un servidor que manda un byte cada 0.1 s."""

    PAUSA = 0.1
    TIMEOUT = (0.5, 1.0)

    def setUp(self):
        cuerpo = (b'{"error":{"codigo":"ERROR-99","mensaje":"No existe la transaccion"}}')
        self.servidor = _ServidorGoteo(cuerpo, self.PAUSA)  # ~7 s en total

    def tearDown(self):
        self.servidor.cerrar()

    def test_el_srm_no_puede_pasarse_del_peor_caso(self):
        peor_caso = 2 * sum(self.TIMEOUT)  # dos intentos, como dice srm.py
        cliente = ClienteSRM(self.servidor.url, TOKEN_FALSO, SALT_FALSO,
                             sesion=_sesion_sin_proxy())
        inicio = time.monotonic()
        with mock.patch.object(modulo_srm, "TIMEOUT_SRM", self.TIMEOUT):
            try:
                cliente.consultar("2026-337308")
            except Exception:
                pass
        self.assertLess(time.monotonic() - inicio, peor_caso + 1.0)

    def test_supabase_no_puede_pasarse_del_peor_caso(self):
        cliente = ClienteSupabase(self.servidor.url, "clave", sesion=_sesion_sin_proxy(),
                                  timeout=self.TIMEOUT)
        inicio = time.monotonic()
        try:
            cliente.registrar_boleto(
                txca="2026-337308", nombre="ANA", apellido_paterno="LÓPEZ",
                apellido_materno=None, telefono="6181234567", clave_catastral="10-001",
                propietario="X", direccion="CALLE 1")
        except Exception:
            pass
        self.assertLess(time.monotonic() - inicio, sum(self.TIMEOUT) + 1.0)


# ===================================== app.py: el registro no es idempotente
class SupuestoReintentarDespuesDeUnCorteMuestraElBoleto(_Base):
    """Si Supabase registra el boleto pero la respuesta se pierde (timeout de
    lectura, conexión cortada), app.py responde 503 "Intenta de nuevo más
    tarde". El ciudadano obedece, y el reintento con EXACTAMENTE los mismos
    datos responde 422 "ya fue registrado": su boleto existe pero nunca lo
    ve ni lo puede descargar, y no hay otra forma de recuperarlo.

    Lo mismo pasa si el formulario se rinde a los 45 s (ver la prueba de
    timeouts) o si waitress tiene sus 8 hilos ocupados y la petición espera
    en cola. Decidir con negocio: o el reintento idéntico devuelve el boleto,
    o hay una forma de consultarlo."""

    def test_el_reintento_identico_devuelve_el_boleto(self):
        bd_real = BDConUnicidad()

        class BDQueSeCorta:
            def __init__(self):
                self.primera = True

            def registrar_boleto(self, **kw):
                resultado = bd_real.registrar_boleto(**kw)
                if self.primera:
                    self.primera = False
                    raise BDNoDisponible("ReadTimeout")  # se guardó, pero no supimos
                return resultado

        self.armar(bd=BDQueSeCorta())
        primera = self.post("/api/registrar", datos_registro())
        self.assertEqual(primera.status_code, 503)
        self.assertIn("2026-337308", bd_real.registrados)  # el boleto SÍ existe

        reintento = self.post("/api/registrar", datos_registro())
        self.assertEqual(reintento.status_code, 200, reintento.get_json())
        self.assertEqual(reintento.get_json()["boleto"]["txca"], "2026-337308")


# ================================== app.py: sin límite por número de folio
class FallaSinLimiteDeIntentosPorFolio(_Base):
    """La fecha de pago es lo único que protege un folio ajeno (está impreso
    en el recibo, y los folios son consecutivos). El límite es por IP:
    cualquiera con unas cuantas IPs (o una sola IPv6, ver
    SupuestoIPv6UnaRed64PorCliente) prueba las fechas que quiera para el
    MISMO folio. En el Octubretón casi todos los pagos caen en ~31 días: una
    IP por fecha basta para sacar la dirección de cualquier folio con
    /api/validar y registrarlo a su nombre con /api/registrar.

    Debe haber un límite de fallos por número de transacción, además del de IP."""

    def test_probar_todas_las_fechas_de_un_folio_desde_varias_ips_se_bloquea(self):
        self.armar(limite=LimiteIntentos(15, 600, ["10.0.0.0/8"]))
        respuestas = []
        for dia in range(1, 31):  # septiembre completo; la buena es el 3
            r = self.post("/api/validar",
                          {"txca": "2026-337308", "fecha_pago": f"2026-09-{dia:02d}"},
                          ip=f"200.1.1.{dia}")  # una IP por intento
            respuestas.append((dia, r.status_code))
        acertadas = [dia for dia, status in respuestas if status == 200]
        self.assertEqual(acertadas, [],
                         "Con una IP por fecha se encontró la fecha de pago del folio "
                         f"(día {acertadas}) y su dirección")
        self.assertIn(429, [s for _, s in respuestas])


# =============================== app.py: el folio no se compara canónico
class SupuestoElFolioEsUnaCadenaCanonica(_Base):
    """app.py acepta ^\\d{4}-\\d{1,10}$ y guarda el folio TAL COMO LLEGA. Si el
    SRM resuelve "2026-0337308" al mismo pago que "2026-337308" (lo normal si
    allá el número se convierte a entero) y devuelve en `txca` lo que se le
    pidió, la base ve dos cadenas distintas: el mismo pago se registra una vez
    por cada cero a la izquierda (hasta 10 dígitos: 4 boletos extra por pago).

    SupuestoTxcaDelSRM (revisión crítica) cubre que el SRM conteste OTRA
    transacción; este caso pasa aunque se compare predio.txca con la petición,
    porque el SRM repite la cadena pedida. Confirmar con el SRM; si acepta
    ceros, el servicio debe guardar una forma canónica del folio."""

    def test_el_mismo_pago_con_ceros_a_la_izquierda_no_da_otro_boleto(self):
        class SRMQueIgnoraCeros:
            def consultar(self, txca):
                anio, numero = txca.split("-")
                if (anio, int(numero)) == ("2026", 337308):
                    return predio(txca=txca)  # repite lo que se le pidió
                raise TransaccionRechazada("ERROR-99", "No existe")

        bd = BDConUnicidad()
        self.armar(srm=SRMQueIgnoraCeros(), bd=bd)
        primero = self.post("/api/registrar", datos_registro(txca="2026-337308"))
        self.assertEqual(primero.status_code, 200)
        for txca in ("2026-0337308", "2026-00337308", "2026-0000337308"):
            with self.subTest(txca=txca):
                r = self.post("/api/registrar", datos_registro(txca=txca))
                self.assertNotEqual(r.status_code, 200)
        self.assertEqual(len(bd.registrados), 1, sorted(bd.registrados))


# ========================== app.py: el ciudadano no ve por qué se rechaza
class FallaElFormularioAceptaUnNombreQueElServicioRechaza(_Base):
    """El formulario deja escribir `\\s` en los nombres, y en Dart (como en
    JavaScript) `\\s` incluye U+FEFF (BOM / espacio de ancho cero), que llega
    al pegar texto copiado de Word, Excel o un PDF. Dart lo cuenta como
    espacio y el formulario lo deja pasar. Python NO lo considera espacio:
    `_texto` no lo quita y RE_NOMBRE lo rechaza con "solo puede contener
    letras y espacios", sin que el ciudadano vea ningún carácter extraño.

    Cualquiera de los dos lados puede corregirlo (ver la prueba gemela en
    test/revision_cuarta_ronda_test.dart); esta prueba pide que el servicio
    lo trate como el espacio que el formulario cree que es."""

    def test_un_bom_pegado_en_el_nombre_no_rechaza_el_registro(self):
        self.armar()
        for campo in ("nombre", "apellido_paterno", "apellido_materno"):
            with self.subTest(campo=campo):
                r = self.post("/api/registrar",
                              datos_registro(**{campo: "MARÍA﻿JOSÉ"}))
                self.assertEqual(r.status_code, 200, r.get_json())


# ================================ limites.py: guardia para la corrección
class GuardiaUnBloqueoNoSeAlarga(unittest.TestCase):
    """Guardia (pasa hoy): un intento rechazado con 429 no cuenta en la
    ventana; si contara, quien sigue intentando quedaría bloqueado para
    siempre. Se deja para que una corrección del límite por folio no lo rompa."""

    def test_los_rechazos_no_alargan_el_bloqueo(self):
        reloj = [0.0]
        lim = LimiteIntentos(2, 10, reloj=lambda: reloj[0])
        self.assertTrue(lim.permitir("200.1.1.1"))
        self.assertTrue(lim.permitir("200.1.1.1"))
        for t in range(1, 10):
            reloj[0] = float(t)
            self.assertFalse(lim.permitir("200.1.1.1"))
        reloj[0] = 10.0
        self.assertTrue(lim.permitir("200.1.1.1"))


if __name__ == "__main__":
    unittest.main()
