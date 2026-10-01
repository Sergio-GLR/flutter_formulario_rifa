"""
Límite de intentos por IP, para que nadie use el servicio publicado en
internet para recorrer números de transacción.

Las IPs de la red municipal (los módulos) NO se limitan: todos los módulos
pueden compartir una misma IP y se bloquearían entre sí.

Es un límite en memoria: suficiente para un solo proceso del servidor. Si
algún día se corren varios procesos, cada uno lleva su propia cuenta.

Las IPv6 se cuentan por red /64: es lo que recibe UNA conexión doméstica, y
contar dirección por dirección dejaría cambiar de IP en cada intento.
"""

import ipaddress
import threading
import time
from collections import defaultdict, deque

PREFIJO_IPV6 = 64


class LimiteIntentos:
    def __init__(self, maximo: int, ventana_segundos: int, redes_exentas=(), reloj=time.monotonic):
        self.maximo = maximo
        self.ventana = ventana_segundos
        self.redes_exentas = [ipaddress.ip_network(r.strip(), strict=False)
                              for r in redes_exentas if r.strip()]
        self._reloj = reloj
        self._intentos = defaultdict(deque)
        self._candado = threading.Lock()
        self._ultima_limpieza = reloj()

    def exenta(self, ip: str) -> bool:
        try:
            direccion = ipaddress.ip_address(ip)
        except ValueError:
            return False
        if direccion.version == 6 and direccion.ipv4_mapped:
            direccion = direccion.ipv4_mapped
        return any(direccion in red for red in self.redes_exentas)

    @staticmethod
    def _clave(ip: str) -> str:
        """IPv4 -> la dirección; IPv6 -> su red /64 (una IPv4 escrita como
        IPv6, ::ffff:a.b.c.d, cuenta como la IPv4)."""
        try:
            direccion = ipaddress.ip_address(ip)
        except ValueError:
            return ip
        if direccion.version == 6:
            if direccion.ipv4_mapped:
                return str(direccion.ipv4_mapped)
            return str(ipaddress.ip_network(f"{direccion}/{PREFIJO_IPV6}", strict=False))
        return str(direccion)

    def _limpiar(self, ahora):
        """Olvida las IPs sin intentos dentro de la ventana, una vez por
        ventana: sin esto el diccionario crece con cada IP que llegó alguna vez."""
        if ahora - self._ultima_limpieza < self.ventana:
            return
        vencidas = [k for k, cola in self._intentos.items()
                    if not cola or ahora - cola[-1] >= self.ventana]
        for k in vencidas:
            del self._intentos[k]
        self._ultima_limpieza = ahora

    def permitir(self, ip: str) -> bool:
        """Registra un intento y dice si todavía está dentro del límite."""
        if self.exenta(ip):
            return True
        ahora = self._reloj()
        with self._candado:
            self._limpiar(ahora)
            cola = self._intentos[self._clave(ip)]
            while cola and ahora - cola[0] >= self.ventana:
                cola.popleft()
            if len(cola) >= self.maximo:
                return False
            cola.append(ahora)
            return True


class LimiteFallos:
    """Fallos por número de transacción, sin importar la IP.

    El límite por IP no protege un folio ajeno: con una IP por intento se
    prueban todas las fechas de pago. Aquí cuenta cada fecha equivocada (o
    folio inexistente) de un MISMO folio; al llegar al máximo, el folio queda
    bloqueado hasta que el fallo más viejo salga de la ventana, aunque llegue
    la fecha correcta. Los aciertos no cuentan.

    Igual que LimiteIntentos: en memoria y por proceso."""

    def __init__(self, maximo: int, ventana_segundos: int, reloj=time.monotonic):
        self.maximo = maximo
        self.ventana = ventana_segundos
        self._reloj = reloj
        self._fallos = defaultdict(deque)
        self._candado = threading.Lock()
        self._ultima_limpieza = reloj()

    def _vigentes(self, clave, ahora):
        cola = self._fallos.get(clave)
        if cola is None:
            return None
        while cola and ahora - cola[0] >= self.ventana:
            cola.popleft()
        if not cola:
            del self._fallos[clave]
            return None
        return cola

    def _limpiar(self, ahora):
        if ahora - self._ultima_limpieza < self.ventana:
            return
        for clave in list(self._fallos):
            self._vigentes(clave, ahora)
        self._ultima_limpieza = ahora

    def bloqueado(self, clave: str) -> bool:
        ahora = self._reloj()
        with self._candado:
            cola = self._vigentes(clave, ahora)
            return cola is not None and len(cola) >= self.maximo

    def fallo(self, clave: str) -> None:
        ahora = self._reloj()
        with self._candado:
            self._limpiar(ahora)
            self._fallos[clave].append(ahora)
