-- Esquema de la Rifa Predial para PostgreSQL 17 o superior.
--
-- Se tomó del backup de Supabase del 19 oct 2026 (solo el esquema public:
-- 3 tablas y 3 funciones), sin los roles, extensiones ni esquemas propios de
-- Supabase. Cargarlo en una base VACÍA, con un usuario dueño de la base:
--
--     psql -d rifa_predial -v ON_ERROR_STOP=1 -f base_datos/esquema.sql
--
-- servicio_rifa se conecta con el rol rifa_servicio, que SOLO puede ejecutar
-- registrar_boleto_rifa: no lee ni escribe las tablas directamente (la función
-- es SECURITY DEFINER y corre con los permisos de su dueño). El script crea el
-- rol sin contraseña; el administrador le da acceso aparte, fuera de Git:
--
--     ALTER ROLE rifa_servicio LOGIN PASSWORD '...';

BEGIN;

-- ------------------------------------------------------------------ tablas

CREATE TABLE public."Pagadores" (
    id_pagador uuid DEFAULT gen_random_uuid() NOT NULL,
    nombre character varying NOT NULL,
    telefono character varying NOT NULL,
    apellido_paterno character varying,
    apellido_materno character varying,
    CONSTRAINT "Pagadores_pkey" PRIMARY KEY (id_pagador)
);

CREATE TABLE public."Predios" (
    clave_catastral character varying NOT NULL,
    propietario_registrado character varying NOT NULL,
    direccion character varying NOT NULL,
    CONSTRAINT "Predios_pkey" PRIMARY KEY (clave_catastral)
);

-- Un boleto por número de transacción: la llave primaria es la que produce el
-- unique_violation que registrar_boleto_rifa traduce a "ya fue registrado".
CREATE TABLE public."Boletos_Rifa" (
    numero_transaccion character varying NOT NULL,
    clave_catastral character varying NOT NULL,
    id_pagador uuid NOT NULL,
    fecha_registro timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT "Boletos_Rifa_pkey" PRIMARY KEY (numero_transaccion),
    CONSTRAINT chk_numero_transaccion_no_vacio CHECK ((TRIM(BOTH FROM numero_transaccion) <> ''::text)),
    CONSTRAINT fk_pagador FOREIGN KEY (id_pagador) REFERENCES public."Pagadores"(id_pagador) ON DELETE RESTRICT,
    CONSTRAINT fk_predio FOREIGN KEY (clave_catastral) REFERENCES public."Predios"(clave_catastral) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------- funciones
-- Copiadas tal cual del backup (incluidos los comentarios de las revisiones).

CREATE FUNCTION public.normalizar_telefono(p_telefono text) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $_$
    SELECT regexp_replace(
               regexp_replace(TRIM(p_telefono), '[\s\-\.\(\)]', '', 'g'),
               '^\+?52(\d{10})$', '\1')
$_$;

CREATE FUNCTION public.obtener_boletos_impresion() RETURNS TABLE(transaccion character varying, nombre_completo text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
    RETURN QUERY
    SELECT
        br.numero_transaccion,
        concat_ws(' ',
                  NULLIF(TRIM(p.nombre), ''),
                  NULLIF(TRIM(p.apellido_paterno), ''),
                  NULLIF(TRIM(p.apellido_materno), '')) AS nombre_completo
    FROM "Boletos_Rifa" br
    JOIN "Pagadores" p ON br.id_pagador = p.id_pagador
    ORDER BY br.fecha_registro ASC;
END;
$$;

CREATE FUNCTION public.registrar_boleto_rifa(p_numero_transaccion character varying, p_nombre_pagador character varying, p_apellido_paterno character varying, p_apellido_materno character varying, p_telefono_pagador character varying, p_clave_catastral character varying, p_propietario_registrado character varying, p_direccion_predio character varying) RETURNS json
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE
    v_id_pagador UUID;
    v_total_boletos INT;
BEGIN
    -- Saneamiento de datos
    p_numero_transaccion := TRIM(p_numero_transaccion);
    p_nombre_pagador := TRIM(p_nombre_pagador);
    p_apellido_paterno := NULLIF(TRIM(p_apellido_paterno), '');   -- '' se guarda como NULL
    p_apellido_materno := NULLIF(TRIM(p_apellido_materno), '');
    p_telefono_pagador := public.normalizar_telefono(p_telefono_pagador);  -- [FALLO 2]
    p_clave_catastral := TRIM(p_clave_catastral);
    p_propietario_registrado := TRIM(p_propietario_registrado);
    p_direccion_predio := TRIM(p_direccion_predio);

    -- [FALLO 4] Campos obligatorios: TRIM('   ') = '' y NOT NULL no lo impide
    IF COALESCE(p_numero_transaccion, '') = '' THEN
        RETURN json_build_object('success', false,
            'message', 'El número de transacción es obligatorio.');
    END IF;
    IF COALESCE(p_nombre_pagador, '') = '' OR COALESCE(p_telefono_pagador, '') = ''
       OR COALESCE(p_clave_catastral, '') = '' THEN
        RETURN json_build_object('success', false,
            'message', 'Nombre, teléfono y clave catastral son obligatorios.');
    END IF;

    -- [FALLO 3] Candado por teléfono: si llegan varias peticiones del mismo
    -- teléfono a la vez, se atienden UNA POR UNA. Así el conteo siguiente ya
    -- ve los boletos de las anteriores. Se suelta solo al terminar la
    -- transacción; teléfonos distintos no se esperan entre sí.
    PERFORM pg_advisory_xact_lock(hashtext('rifa_telefono:' || p_telefono_pagador));

    -- 1. Validar el límite de 5 boletos por NÚMERO DE TELÉFONO globalmente
    SELECT COUNT(*) INTO v_total_boletos
    FROM "Boletos_Rifa" br
    JOIN "Pagadores" p ON br.id_pagador = p.id_pagador
    WHERE p.telefono = p_telefono_pagador;

    IF v_total_boletos >= 5 THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Este número de teléfono ya ha alcanzado el límite de 5 boletos registrados en total.'
        );
    END IF;

    -- 2. Manejo del Pagador. IS NOT DISTINCT FROM hace que NULL coincida con
    --    NULL (con '=' una persona sin apellido materno se duplicaba cada vez).
    SELECT id_pagador INTO v_id_pagador
    FROM "Pagadores"
    WHERE telefono = p_telefono_pagador
      AND nombre = p_nombre_pagador
      AND apellido_paterno IS NOT DISTINCT FROM p_apellido_paterno
      AND apellido_materno IS NOT DISTINCT FROM p_apellido_materno
    LIMIT 1;

    -- 3. Si no existe esa combinación exacta, es un registro nuevo
    IF v_id_pagador IS NULL THEN
        INSERT INTO "Pagadores" (id_pagador, nombre, apellido_paterno, apellido_materno, telefono)
        VALUES (gen_random_uuid(), p_nombre_pagador, p_apellido_paterno, p_apellido_materno, p_telefono_pagador)
        RETURNING id_pagador INTO v_id_pagador;
    END IF;

    -- 4. Manejo del Predio (Upsert) -- sin cambios
    INSERT INTO "Predios" (clave_catastral, propietario_registrado, direccion)
    VALUES (p_clave_catastral, p_propietario_registrado, p_direccion_predio)
    ON CONFLICT (clave_catastral)
    DO UPDATE SET
        propietario_registrado = EXCLUDED.propietario_registrado,
        direccion = EXCLUDED.direccion;

    -- 5. Inserción del Boleto
    INSERT INTO "Boletos_Rifa" (numero_transaccion, clave_catastral, id_pagador, fecha_registro)
    VALUES (p_numero_transaccion, p_clave_catastral, v_id_pagador, now());

    RETURN json_build_object(
        'success', true,
        'message', 'Registro completado exitosamente.'
    );

EXCEPTION WHEN unique_violation THEN
    RETURN json_build_object(
        'success', false,
        'message', 'Este número de transacción ya fue registrado anteriormente.'
    );
WHEN OTHERS THEN
    -- [PASO 3] El detalle técnico se guarda SOLO en los logs de Postgres
    -- (el log del servidor), nunca se envía al navegador.
    RAISE LOG 'registrar_boleto_rifa: error inesperado [%] % (txca=%)',
        SQLSTATE, SQLERRM, p_numero_transaccion;
    RETURN json_build_object(
        'success', false,
        'message', 'No pudimos registrar tu boleto en este momento. Intenta de nuevo más tarde.'
    );
END;
$$;


-- ----------------------------------------------------------------- permisos
-- En PostgreSQL toda función nueva la puede ejecutar PUBLIC: se quita y solo
-- rifa_servicio puede llamar a registrar_boleto_rifa.

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rifa_servicio') THEN
        CREATE ROLE rifa_servicio NOLOGIN;
    END IF;
END
$$;

REVOKE ALL ON FUNCTION public.normalizar_telefono(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.obtener_boletos_impresion() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.registrar_boleto_rifa(character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying) FROM PUBLIC;
REVOKE ALL ON public."Pagadores", public."Predios", public."Boletos_Rifa" FROM PUBLIC;

GRANT USAGE ON SCHEMA public TO rifa_servicio;
GRANT EXECUTE ON FUNCTION public.registrar_boleto_rifa(character varying, character varying, character varying, character varying, character varying, character varying, character varying, character varying) TO rifa_servicio;

COMMIT;
