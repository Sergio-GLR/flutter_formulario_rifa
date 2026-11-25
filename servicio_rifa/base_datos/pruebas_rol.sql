-- SOLO para el contenedor de pruebas (compose.pruebas.yaml): da acceso al rol
-- de la app con una contraseña de prueba. En el servidor real la contraseña la
-- pone el administrador y no se guarda en Git.
ALTER ROLE rifa_servicio LOGIN PASSWORD 'pruebas_rifa';
