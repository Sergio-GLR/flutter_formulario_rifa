"""
Límite de intentos por IP, para que nadie use el servicio publicado en
internet para recorrer números de transacción.

Las IPs de la red municipal (los módulos) NO se limitan: todos los módulos
pueden compartir una misma IP y se bloquearían entre sí.

Es un límite en memoria: suficiente para un solo proceso del servidor. Si
algún día se corren varios procesos, cada uno lleva su propia cuenta.
"""

import ipaddress
import threading
import time
from collections import defaultdict, deque


class LimiteIntentos:
    def __init__(self, maximo: int, ventana_segundos: int, redes_exentas=(), reloj=time.monotonic):
        self.maximo = maximo
        self.ventana = ventana_segundos
        self.redes_exentas = [ipaddress.ip_network(r.strip(), strict=False)
                              for r in redes_exentas if r.strip()]
        self._reloj = reloj
        self._intentos = defaultdict(deque)
        self._candado = threading.Lock()

    def exenta(self, ip: str) -> bool:
        try:
            direccion = ipaddress.ip_address(ip)
        except ValueError:
            return False
        return any(direccion in red for red in self.redes_exentas)

    def permitir(self, ip: str) -> bool:
        """Registra un intento y dice si todavía está dentro del límite."""
        if self.exenta(ip):
            return True
        ahora = self._reloj()
        with self._candado:
            cola = self._intentos[ip]
            while cola and ahora - cola[0] >= self.ventana:
                cola.popleft()
            if len(cola) >= self.maximo:
                return False
            cola.append(ahora)
            return True
