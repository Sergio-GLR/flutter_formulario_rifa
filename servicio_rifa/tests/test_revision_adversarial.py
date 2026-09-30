"""
Revisión adversarial del servicio interno (29 sep 2026).

Tercera ronda: se intentó romper lo que ya se había corregido en las
revisiones anteriores (test_servicio y test_revision_critica). NO se corrigió
nada: estas pruebas FALLAN con el código actual y deben pasar cuando se
corrija cada defecto. Correr desde la carpeta servicio_rifa:

    python -m unittest -v tests.test_revision_adversarial

Convención (igual que en test_revision_critica):
  * clase Falla...    -> defecto confirmado.
  * clase Supuesto... -> el código asume algo que no está garantizado; hay que
                         confirmarlo con el SRM / Supabase / redes antes de
                         decidir. Si se confirma, la prueba se ajusta o se borra.
"""

import copy
import logging
import os
import re
import sys
import unittest

import requests

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import MSG_PERSONA_MORAL, crear_app  # noqa: E402
from bd import ClienteSupabase  # noqa: E402
from limites import LimiteIntentos  # noqa: E402
from srm import ClienteSRM, SRMNoDisponible  # noqa: E402

from tests.test_servicio import (  # noqa: E402
    OK_SRM, SALT_FALSO, TOKEN_FALSO, BDFalsa, _Base, _Resp, _SesionFalla,
    datos_registro)

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def setUpModule():
    # Algunas pruebas provocan errores 500 a propósito; no ensuciar la salida.
    logging.disable(logging.CRITICAL)


def tearDownModule():
    logging.disable(logging.NOTSET)


def srm_que_responde(**cambios):
    """ClienteSRM real con una respuesta del SRM modificada."""
    datos = copy.deepcopy(OK_SRM)
    datos["response"].update(cambios)
    return ClienteSRM("https://srm", TOKEN_FALSO, SALT_FALSO, sesion=_SesionFalla(_Resp(datos)))


# ================================================== app.py: mensaje de la BD
class FallaMensajeDeLaBDSinFiltrar(_Base):
    """app.py devuelve `resultado["message"]` de registrar_boleto_rifa tal
    cual al ciudadano. La revisión de seguridad (hallazgo 5) encontró que la
    función SQL responde {success: false, message: SQLERRM} en errores
    inesperados, y la revisión crítica dejó fuera la función SQL ("No se
    revisó registrar_boleto_rifa"). Si ese cambio no se hizo, el servicio es
    la única barrera y no filtra nada: el ciudadano ve nombres de tablas,
    columnas y restricciones. test_error_de_bd_no_expone_detalles solo cubre
    el camino de BDNoDisponible, no este.

    Corregido (30 sep 2026): la función SQL actual ya manda SQLERRM solo al
    log de Postgres, y app.py solo deja pasar los rechazos que la función
    escribe (RECHAZOS_DE_LA_BD). Esta prueba queda como protección por si
    alguien vuelve a poner SQLERRM en la función."""

    TECNICOS = [
        'null value in column "clave_catastral" of relation "Predios" '
        'violates not-null constraint',
        'duplicate key value violates unique constraint "boletos_pkey"',
        'function registrar_boleto_rifa(text, text) does not exist',
        'permission denied for table Boletos',
        # Postgres con mensajes en español
        'la relación «Boletos_Rifa» ya existe',
        # Parecido a un rechazo conocido, pero no idéntico
        'Este número de transacción ya fue registrado anteriormente. '
        'Key (numero_transaccion)=(2026-337308) already exists.',
    ]

    def test_un_error_tecnico_de_la_bd_no_llega_al_ciudadano(self):
        for mensaje in self.TECNICOS:
            with self.subTest(mensaje=mensaje):
                self.armar(bd=BDFalsa(resultado={"success": False, "message": mensaje}))
                r = self.post("/api/registrar", datos_registro())
                self.assertIs(r.json["ok"], False)
                cuerpo = r.get_data(as_text=True)
                for fuga in ("relation", "relación", "constraint", "column", "function",
                             "Predios", "Boletos", "permission", "numero_transaccion"):
                    self.assertNotIn(fuga, cuerpo)

    def test_un_exito_no_repite_el_mensaje_de_la_bd(self):
        self.armar(bd=BDFalsa(resultado={"success": True, "message": "INSERT 0 1 into Boletos"}))
        r = self.post("/api/registrar", datos_registro())
        self.assertIs(r.json["ok"], True)
        self.assertNotIn("Boletos", r.get_data(as_text=True))

    def test_los_rechazos_de_negocio_si_llegan_al_ciudadano(self):
        """Guardia: el filtro no debe tapar lo que el ciudadano necesita saber.
        Mensajes copiados de la función SQL registrar_boleto_rifa."""
        for mensaje in (
                "Este número de teléfono ya ha alcanzado el límite de 5 boletos "
                "registrados en total.",
                "Este número de transacción ya fue registrado anteriormente.",
                "No pudimos registrar tu boleto en este momento. Intenta de nuevo "
                "más tarde."):
            with self.subTest(mensaje=mensaje):
                self.armar(bd=BDFalsa(resultado={"success": False, "message": mensaje}))
                r = self.post("/api/registrar", datos_registro())
                self.assertEqual((r.status_code, r.json["mensaje"]), (422, mensaje))


# ================================================== app.py: tamaño del cuerpo
class FallaCuerpoSinLimite(_Base):
    """No hay MAX_CONTENT_LENGTH: Flask lee el cuerpo completo a memoria antes
    de validar nada. waitress acepta hasta 1 GB por petición, así que con el
    límite de 15 intentos una sola IP puede hacer que el proceso cargue 15 GB
    cada 10 minutos. Los datos válidos más largos caben en ~400 bytes.

    Además, un JSON muy anidado (`[[[[...]]]]`) provoca RecursionError, que
    no es ValueError: get_json(silent=True) no lo atrapa y el servicio
    responde 500 y escribe una traza completa en el log por cada petición.

    Corregido (30 sep 2026): MAX_CUERPO_BYTES (16 KB) en Flask y en waitress
    (servidor.py), y _cuerpo() convierte el RecursionError en un 400."""

    def test_un_cuerpo_enorme_se_rechaza_con_413(self):
        self.armar()
        enorme = '{"txca": "' + "9" * (2 * 1024 * 1024) + '"}'  # 2 MB
        r = self.cliente.post("/api/validar", data=enorme, content_type="application/json",
                              environ_base={"REMOTE_ADDR": "200.1.1.1"})
        self.assertEqual(r.status_code, 413)
        self.assertTrue(r.is_json, "Respondió HTML en vez de JSON")
        self.assertIs(r.json["ok"], False)
        self.assertEqual(self.srm.consultas, [])

    def test_json_muy_anidado_responde_400(self):
        self.armar()
        # Menos de 16 KB (para no chocar con el tope de tamaño) pero 2,000
        # niveles: el doble del límite de recursión de Python.
        for crudo in ("[" * 2000 + "]" * 2000,
                      '{"a":' * 2000 + "1" + "}" * 2000):
            with self.subTest(cuerpo=crudo[:10] + "..."):
                r = self.cliente.post("/api/validar", data=crudo,
                                      content_type="application/json",
                                      environ_base={"REMOTE_ADDR": "200.1.1.1"})
                self.assertEqual(r.status_code, 400)
                self.assertIs(r.json["ok"], False)

    def test_el_registro_valido_mas_grande_cabe(self):
        """Guardia: el tope no debe dejar fuera a nadie. Nombre y apellidos de
        60 letras, todas con acento (2 bytes cada una en UTF-8)."""
        self.armar()
        largo = "Á" * 60
        r = self.post("/api/registrar", datos_registro(
            nombre=largo, apellido_paterno=largo, apellido_materno=largo))
        self.assertEqual(r.status_code, 200, r.json)


# ================================================== tiempos: servicio vs. formulario
class FallaElFormularioSeRindeAntesQueElServicio(unittest.TestCase):
    """El formulario espera 45 s (servicio_rifa.dart, _timeout). El servicio,
    en /api/registrar, puede tardar más: requests usa el timeout escalar
    para conectar Y para leer, el SRM se intenta 2 veces y luego Supabase.
    Peor caso: 2 x (12 + 12) + (15 + 15) = 78 s.

    Si el formulario se rinde primero, el ciudadano ve "El servidor tardó
    demasiado" aunque el servicio SÍ lo registre. Al reintentar recibe
    "ya registrado" y nunca ve su boleto.

    Corregido (30 sep 2026): timeouts (conectar, leer) separados,
    srm.TIMEOUT_SRM = (3, 10) y bd.TIMEOUT_BD = (5, 8). Peor caso: 39 s."""

    def test_el_peor_caso_del_servicio_cabe_en_la_espera_del_formulario(self):
        with open(os.path.join(RAIZ, "lib", "servicios", "servicio_rifa.dart"),
                  encoding="utf-8") as f:
            dart = f.read()
        espera_formulario = int(re.search(
            r"_timeout\s*=\s*Duration\(seconds:\s*(\d+)\)", dart).group(1))

        # Recorre /api/registrar con el SRM fallando una vez por red (el caso
        # que provoca el reintento) y anota los timeouts que se usan.
        timeouts = []

        class Sesion(_SesionFalla):
            def post(self, url, **kw):
                timeouts.append(kw["timeout"])
                return super().post(url, **kw)

        srm = ClienteSRM("https://srm", TOKEN_FALSO, SALT_FALSO,
                         sesion=Sesion(requests.ConnectionError(), _Resp(OK_SRM)))
        bd = ClienteSupabase("https://bd", "clave",
                             sesion=Sesion(_Resp({"success": True, "message": "ok"})))
        app = crear_app(srm=srm, bd=bd, limite=LimiteIntentos(1000, 600), config={})
        r = app.test_client().post("/api/registrar", json=datos_registro(),
                                   environ_base={"REMOTE_ADDR": "200.1.1.1"})
        self.assertEqual(r.status_code, 200, r.json)

        # Un timeout escalar de requests aplica a conectar y a leer por separado
        peor_caso = sum(2 * t if isinstance(t, (int, float)) else sum(t) for t in timeouts)
        self.assertLess(peor_caso, espera_formulario,
                        f"El servicio puede tardar {peor_caso} s y el formulario "
                        f"solo espera {espera_formulario} s (timeouts: {timeouts})")


# ================================================== supuestos sobre el SRM
class SupuestoTipoPersonaSinAcento(_Base):
    """app.py compara `predio.tipo_persona != "FISICA"` (sin acento). Las dos
    revisiones anteriores y el aviso del formulario escriben "FÍSICA". Si el
    SRM devuelve t_persona con acento ("FÍSICA" o "Física"), TODOS los
    ciudadanos quedan fuera con "El sorteo es exclusivo para personas
    físicas". Ninguna prueba usa una respuesta real del SRM: todas usan
    "FISICA". Hay que confirmar con el SRM el valor exacto (o normalizar
    acentos antes de comparar).

    Respuesta (Propuesta Técnica del SRM, sección 5.2): "Valor observado:
    FISICA (considerar también MORAL si aparece)". Observado, no garantizado,
    así que srm._leer_tipo_persona quita acentos antes de comparar."""

    def test_fisica_con_acento_es_persona_fisica(self):
        for valor in ("FISICA", "FÍSICA", "Física", "física", " fisica "):
            with self.subTest(t_persona=valor):
                self.armar(srm=srm_que_responde(t_persona=valor))
                r = self.post("/api/validar", {"txca": "2026-337308",
                                               "fecha_pago": "2026-09-03"})
                self.assertEqual(r.status_code, 200, r.json)

    def test_moral_sigue_rechazada_en_cualquier_forma(self):
        """Guardia: normalizar no debe dejar pasar a una persona moral."""
        for valor in ("MORAL", "Moral", "moral", "PERSONA MORAL", ""):
            with self.subTest(t_persona=valor):
                self.armar(srm=srm_que_responde(t_persona=valor))
                r = self.post("/api/validar", {"txca": "2026-337308",
                                               "fecha_pago": "2026-09-03"})
                self.assertEqual((r.status_code, r.json["mensaje"]), (422, MSG_PERSONA_MORAL))


class SupuestoFechaDelSRMConCeros(unittest.TestCase):
    """srm._leer_fecha_pago corta los primeros 10 caracteres y exige
    'DD-MM-YYYY'. Si el SRM manda el día o el mes sin cero ('3-9-2026
    9:05:00'), el corte deja '3-9-2026 9' y TODAS esas consultas responden
    503 "servicio no disponible". El ciudadano reintenta y nunca pasa. El
    formato solo se vio en un ejemplo de la documentación.

    Respuesta (Propuesta Técnica del SRM, sección 5.2): "Formato observado:
    DD-MM-YYYY HH:mm:ss". Observado, no garantizado, así que
    srm._leer_fecha_pago toma lo que va antes del espacio."""

    def test_dia_y_mes_sin_cero(self):
        for texto in ("3-09-2026 13:24:31", "03-9-2026 13:24:31", "3-9-2026 9:05:00",
                      "03-09-2026 13:24:31", "03-09-2026", " 03-09-2026  13:24:31 "):
            with self.subTest(fecha_pago=texto):
                srm = srm_que_responde(fecha_pago=texto)
                try:
                    fecha = srm.consultar("2026-337308").fecha_pago
                except SRMNoDisponible:
                    self.fail(f"'{texto}' se trató como SRM caído")
                self.assertEqual((fecha.year, fecha.month, fecha.day), (2026, 9, 3))

    def test_una_fecha_ilegible_sigue_siendo_srm_no_disponible(self):
        """Guardia: tolerar los ceros no debe aceptar otros formatos (y nunca
        un error 500 por una fecha vacía)."""
        for texto in ("", "   ", "2026-09-03 13:24:31", "03/09/2026", "31-02-2026", None):
            with self.subTest(fecha_pago=texto):
                with self.assertRaises(SRMNoDisponible):
                    srm_que_responde(fecha_pago=texto).consultar("2026-337308")


class SupuestoPersonaMoralSinPropietario(_Base):
    """srm.py arma el Predio (propietario.strip(), domicilio.strip()...) ANTES
    de que app.py revise t_persona. Si para una persona MORAL el SRM manda
    propietario o domicilio en null, el ciudadano recibe 503 "servicio no
    disponible" (y reintenta) en lugar de "exclusivo para personas físicas"."""

    def test_moral_sin_propietario_recibe_el_mensaje_de_persona_moral(self):
        for campo in ("propietario", "domicilio", "cc"):
            with self.subTest(nulo=campo):
                self.armar(srm=srm_que_responde(t_persona="MORAL", **{campo: None}))
                r = self.post("/api/validar", {"txca": "2026-337308",
                                               "fecha_pago": "2026-09-03"})
                self.assertEqual((r.status_code, r.json["mensaje"]), (422, MSG_PERSONA_MORAL))


# ================================================== supuesto sobre IPv6
class SupuestoIPv6UnaRed64PorCliente(unittest.TestCase):
    """limites.py agrupa IPv6 por /64 porque "es lo que recibe UNA conexión
    doméstica". Muchos proveedores delegan /56 (256 redes /64) o /48 (65,536)
    a cada cliente. Con /56, un solo hogar tiene 256 x 15 = 3,840 intentos
    cada 10 minutos: suficiente para probar todas las fechas de pago de un
    año para decenas de folios ajenos (la fecha es el único dato que protege
    un folio ajeno). Hay que confirmar qué prefijo delegan los proveedores
    de la región antes de decidir el tamaño del grupo."""

    def test_redes_64_de_la_misma_56_comparten_limite(self):
        lim = LimiteIntentos(3, 600)
        permitidos = [lim.permitir(f"2001:db8:0:{i:x}::1") for i in range(10)]
        self.assertEqual(permitidos.count(True), 3,
                         "Cada /64 de la misma /56 obtuvo su propia cuenta")


if __name__ == "__main__":
    unittest.main()
