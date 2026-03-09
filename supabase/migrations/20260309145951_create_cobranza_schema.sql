/*
  # Base de datos completa - Sistema de Gestión de Cobranza

  ## Descripción General
  Sistema de gestión de préstamos y cobranza con tres niveles de usuarios:
  - Admin: Control total del sistema
  - Auxiliar: Acceso de solo lectura a reportes y dashboards
  - Cobrador: Gestión de clientes, préstamos, cobros y gastos propios

  ## 1. Tablas Principales

  ### usuarios
  Perfil extendido de usuarios vinculado a auth.users
  - `id` (uuid, FK a auth.users)
  - `nombre_completo` (text)
  - `telefono` (text)
  - `rol` (enum: admin, auxiliar, cobrador)
  - `estado` (boolean, activo/inactivo)
  - `ultima_actividad` (timestamptz)
  - `created_at`, `updated_at`

  ### clientes
  Clientes gestionados por cobradores
  - `id` (uuid)
  - `cobrador_id` (uuid, FK a usuarios)
  - `nombre_completo` (text)
  - `cedula` (text, única)
  - `direccion` (text)
  - `telefono` (text)
  - `estado` (boolean)
  - `fecha_ultimo_contacto` (timestamptz)
  - `created_at`, `updated_at`

  ### prestamos
  Préstamos asignados a clientes
  - `id` (uuid)
  - `cliente_id` (uuid, FK a clientes)
  - `cobrador_id` (uuid, FK a usuarios)
  - `monto_base` (numeric)
  - `porcentaje_interes` (numeric, default 20)
  - `total_a_pagar` (numeric, calculado)
  - `monto_pagado` (numeric)
  - `saldo_pendiente` (numeric)
  - `estado` (enum: activo, completado, renovado)
  - `fecha_creacion` (timestamptz)
  - `created_at`, `updated_at`

  ### pagos
  Registro de pagos/cobros realizados
  - `id` (uuid)
  - `prestamo_id` (uuid, FK a prestamos)
  - `cobrador_id` (uuid, FK a usuarios)
  - `monto` (numeric)
  - `fecha_hora` (timestamptz)
  - `created_at`

  ### gastos
  Gastos operativos de cobradores
  - `id` (uuid)
  - `cobrador_id` (uuid, FK a usuarios)
  - `categoria` (text)
  - `monto` (numeric)
  - `descripcion` (text)
  - `fecha` (date)
  - `created_at`

  ### cierres_caja
  Cierres de caja diarios por cobrador
  - `id` (uuid)
  - `cobrador_id` (uuid, FK a usuarios)
  - `fecha` (date)
  - `total_cobrado` (numeric)
  - `total_gastos` (numeric)
  - `neto` (numeric)
  - `tipo` (enum: manual, automatico)
  - `created_at`

  ### notificaciones
  Sistema de notificaciones para usuarios
  - `id` (uuid)
  - `usuario_id` (uuid, FK a usuarios)
  - `tipo` (text)
  - `mensaje` (text)
  - `leida` (boolean)
  - `created_at`

  ## 2. Seguridad RLS
  - Cobradores: Solo acceso a sus propios datos
  - Auxiliares: Solo lectura de datos agregados
  - Admin: Acceso completo

  ## 3. Funciones Automáticas
  - Cálculo automático del total a pagar en préstamos
  - Actualización automática de saldo pendiente al registrar pagos
  - Marcado automático de préstamos como completados
  - Trigger para actualizar ultima_actividad del usuario
*/

-- =====================================================
-- 1. TIPOS ENUMERADOS
-- =====================================================

DO $$ BEGIN
  CREATE TYPE rol_usuario AS ENUM ('admin', 'auxiliar', 'cobrador');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE estado_prestamo AS ENUM ('activo', 'completado', 'renovado');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE tipo_cierre AS ENUM ('manual', 'automatico');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- =====================================================
-- 2. TABLA: usuarios
-- =====================================================

CREATE TABLE IF NOT EXISTS usuarios (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre_completo text NOT NULL,
  telefono text,
  rol rol_usuario NOT NULL DEFAULT 'cobrador',
  estado boolean NOT NULL DEFAULT true,
  ultima_actividad timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE usuarios ENABLE ROW LEVEL SECURITY;

-- Políticas para usuarios
CREATE POLICY "Admin puede ver todos los usuarios"
  ON usuarios FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Usuarios pueden ver su propio perfil"
  ON usuarios FOR SELECT
  TO authenticated
  USING (id = auth.uid());

CREATE POLICY "Admin puede crear usuarios"
  ON usuarios FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Admin puede actualizar usuarios"
  ON usuarios FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Usuarios pueden actualizar su ultima_actividad"
  ON usuarios FOR UPDATE
  TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- =====================================================
-- 3. TABLA: clientes
-- =====================================================

CREATE TABLE IF NOT EXISTS clientes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cobrador_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  nombre_completo text NOT NULL,
  cedula text NOT NULL UNIQUE,
  direccion text,
  telefono text,
  estado boolean NOT NULL DEFAULT true,
  fecha_ultimo_contacto timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE clientes ENABLE ROW LEVEL SECURITY;

-- Políticas para clientes
CREATE POLICY "Admin puede ver todos los clientes"
  ON clientes FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Auxiliar puede ver todos los clientes"
  ON clientes FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'auxiliar'
    )
  );

CREATE POLICY "Cobrador puede ver sus propios clientes"
  ON clientes FOR SELECT
  TO authenticated
  USING (cobrador_id = auth.uid());

CREATE POLICY "Cobrador puede crear clientes"
  ON clientes FOR INSERT
  TO authenticated
  WITH CHECK (
    cobrador_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'cobrador'
    )
  );

CREATE POLICY "Cobrador puede actualizar sus propios clientes"
  ON clientes FOR UPDATE
  TO authenticated
  USING (cobrador_id = auth.uid())
  WITH CHECK (cobrador_id = auth.uid());

-- =====================================================
-- 4. TABLA: prestamos
-- =====================================================

CREATE TABLE IF NOT EXISTS prestamos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cliente_id uuid NOT NULL REFERENCES clientes(id) ON DELETE CASCADE,
  cobrador_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  monto_base numeric(10, 2) NOT NULL CHECK (monto_base > 0),
  porcentaje_interes numeric(5, 2) NOT NULL DEFAULT 20,
  total_a_pagar numeric(10, 2) NOT NULL DEFAULT 0,
  monto_pagado numeric(10, 2) NOT NULL DEFAULT 0,
  saldo_pendiente numeric(10, 2) NOT NULL DEFAULT 0,
  estado estado_prestamo NOT NULL DEFAULT 'activo',
  fecha_creacion timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE prestamos ENABLE ROW LEVEL SECURITY;

-- Políticas para préstamos
CREATE POLICY "Admin puede ver todos los prestamos"
  ON prestamos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Auxiliar puede ver todos los prestamos"
  ON prestamos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'auxiliar'
    )
  );

CREATE POLICY "Cobrador puede ver sus propios prestamos"
  ON prestamos FOR SELECT
  TO authenticated
  USING (cobrador_id = auth.uid());

CREATE POLICY "Cobrador puede crear prestamos"
  ON prestamos FOR INSERT
  TO authenticated
  WITH CHECK (
    cobrador_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'cobrador'
    )
  );

CREATE POLICY "Cobrador puede actualizar sus propios prestamos"
  ON prestamos FOR UPDATE
  TO authenticated
  USING (cobrador_id = auth.uid())
  WITH CHECK (cobrador_id = auth.uid());

-- =====================================================
-- 5. TABLA: pagos
-- =====================================================

CREATE TABLE IF NOT EXISTS pagos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  prestamo_id uuid NOT NULL REFERENCES prestamos(id) ON DELETE CASCADE,
  cobrador_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  monto numeric(10, 2) NOT NULL CHECK (monto > 0),
  fecha_hora timestamptz DEFAULT now(),
  created_at timestamptz DEFAULT now()
);

ALTER TABLE pagos ENABLE ROW LEVEL SECURITY;

-- Políticas para pagos
CREATE POLICY "Admin puede ver todos los pagos"
  ON pagos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Auxiliar puede ver todos los pagos"
  ON pagos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'auxiliar'
    )
  );

CREATE POLICY "Cobrador puede ver sus propios pagos"
  ON pagos FOR SELECT
  TO authenticated
  USING (cobrador_id = auth.uid());

CREATE POLICY "Cobrador puede crear pagos"
  ON pagos FOR INSERT
  TO authenticated
  WITH CHECK (
    cobrador_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'cobrador'
    )
  );

-- =====================================================
-- 6. TABLA: gastos
-- =====================================================

CREATE TABLE IF NOT EXISTS gastos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cobrador_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  categoria text NOT NULL,
  monto numeric(10, 2) NOT NULL CHECK (monto > 0),
  descripcion text,
  fecha date DEFAULT CURRENT_DATE,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE gastos ENABLE ROW LEVEL SECURITY;

-- Políticas para gastos
CREATE POLICY "Admin puede ver todos los gastos"
  ON gastos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Auxiliar puede ver todos los gastos"
  ON gastos FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'auxiliar'
    )
  );

CREATE POLICY "Cobrador puede ver sus propios gastos"
  ON gastos FOR SELECT
  TO authenticated
  USING (cobrador_id = auth.uid());

CREATE POLICY "Cobrador puede crear gastos"
  ON gastos FOR INSERT
  TO authenticated
  WITH CHECK (
    cobrador_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'cobrador'
    )
  );

-- =====================================================
-- 7. TABLA: cierres_caja
-- =====================================================

CREATE TABLE IF NOT EXISTS cierres_caja (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cobrador_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  fecha date NOT NULL,
  total_cobrado numeric(10, 2) NOT NULL DEFAULT 0,
  total_gastos numeric(10, 2) NOT NULL DEFAULT 0,
  neto numeric(10, 2) NOT NULL DEFAULT 0,
  tipo tipo_cierre NOT NULL DEFAULT 'manual',
  created_at timestamptz DEFAULT now(),
  UNIQUE(cobrador_id, fecha)
);

ALTER TABLE cierres_caja ENABLE ROW LEVEL SECURITY;

-- Políticas para cierres de caja
CREATE POLICY "Admin puede ver todos los cierres"
  ON cierres_caja FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'admin'
    )
  );

CREATE POLICY "Auxiliar puede ver todos los cierres"
  ON cierres_caja FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'auxiliar'
    )
  );

CREATE POLICY "Cobrador puede ver sus propios cierres"
  ON cierres_caja FOR SELECT
  TO authenticated
  USING (cobrador_id = auth.uid());

CREATE POLICY "Cobrador puede crear cierres"
  ON cierres_caja FOR INSERT
  TO authenticated
  WITH CHECK (
    cobrador_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM usuarios u
      WHERE u.id = auth.uid() AND u.rol = 'cobrador'
    )
  );

-- =====================================================
-- 8. TABLA: notificaciones
-- =====================================================

CREATE TABLE IF NOT EXISTS notificaciones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  usuario_id uuid NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  tipo text NOT NULL,
  mensaje text NOT NULL,
  leida boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE notificaciones ENABLE ROW LEVEL SECURITY;

-- Políticas para notificaciones
CREATE POLICY "Usuarios pueden ver sus propias notificaciones"
  ON notificaciones FOR SELECT
  TO authenticated
  USING (usuario_id = auth.uid());

CREATE POLICY "Usuarios pueden actualizar sus propias notificaciones"
  ON notificaciones FOR UPDATE
  TO authenticated
  USING (usuario_id = auth.uid())
  WITH CHECK (usuario_id = auth.uid());

CREATE POLICY "Sistema puede crear notificaciones"
  ON notificaciones FOR INSERT
  TO authenticated
  WITH CHECK (true);

-- =====================================================
-- 9. FUNCIONES Y TRIGGERS
-- =====================================================

-- Función para calcular total a pagar en préstamos
CREATE OR REPLACE FUNCTION calcular_total_prestamo()
RETURNS TRIGGER AS $$
BEGIN
  NEW.total_a_pagar := NEW.monto_base + (NEW.monto_base * NEW.porcentaje_interes / 100);
  NEW.saldo_pendiente := NEW.total_a_pagar - NEW.monto_pagado;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_calcular_total_prestamo ON prestamos;
CREATE TRIGGER trigger_calcular_total_prestamo
  BEFORE INSERT OR UPDATE ON prestamos
  FOR EACH ROW
  EXECUTE FUNCTION calcular_total_prestamo();

-- Función para actualizar préstamo al registrar pago
CREATE OR REPLACE FUNCTION actualizar_prestamo_pago()
RETURNS TRIGGER AS $$
BEGIN
  -- Actualizar monto pagado y saldo pendiente
  UPDATE prestamos
  SET 
    monto_pagado = monto_pagado + NEW.monto,
    saldo_pendiente = saldo_pendiente - NEW.monto,
    updated_at = now()
  WHERE id = NEW.prestamo_id;

  -- Marcar como completado si saldo llega a cero o menos
  UPDATE prestamos
  SET estado = 'completado'
  WHERE id = NEW.prestamo_id AND saldo_pendiente <= 0;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_actualizar_prestamo_pago ON pagos;
CREATE TRIGGER trigger_actualizar_prestamo_pago
  AFTER INSERT ON pagos
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_prestamo_pago();

-- Función para actualizar updated_at automáticamente
CREATE OR REPLACE FUNCTION actualizar_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_usuarios_updated_at ON usuarios;
CREATE TRIGGER trigger_usuarios_updated_at
  BEFORE UPDATE ON usuarios
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_updated_at();

DROP TRIGGER IF EXISTS trigger_clientes_updated_at ON clientes;
CREATE TRIGGER trigger_clientes_updated_at
  BEFORE UPDATE ON clientes
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_updated_at();

DROP TRIGGER IF EXISTS trigger_prestamos_updated_at ON prestamos;
CREATE TRIGGER trigger_prestamos_updated_at
  BEFORE UPDATE ON prestamos
  FOR EACH ROW
  EXECUTE FUNCTION actualizar_updated_at();

-- =====================================================
-- 10. ÍNDICES PARA MEJORAR RENDIMIENTO
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_clientes_cobrador ON clientes(cobrador_id);
CREATE INDEX IF NOT EXISTS idx_clientes_cedula ON clientes(cedula);
CREATE INDEX IF NOT EXISTS idx_prestamos_cliente ON prestamos(cliente_id);
CREATE INDEX IF NOT EXISTS idx_prestamos_cobrador ON prestamos(cobrador_id);
CREATE INDEX IF NOT EXISTS idx_prestamos_estado ON prestamos(estado);
CREATE INDEX IF NOT EXISTS idx_pagos_prestamo ON pagos(prestamo_id);
CREATE INDEX IF NOT EXISTS idx_pagos_cobrador ON pagos(cobrador_id);
CREATE INDEX IF NOT EXISTS idx_pagos_fecha ON pagos(fecha_hora);
CREATE INDEX IF NOT EXISTS idx_gastos_cobrador ON gastos(cobrador_id);
CREATE INDEX IF NOT EXISTS idx_gastos_fecha ON gastos(fecha);
CREATE INDEX IF NOT EXISTS idx_cierres_cobrador_fecha ON cierres_caja(cobrador_id, fecha);
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario ON notificaciones(usuario_id);
CREATE INDEX IF NOT EXISTS idx_usuarios_rol ON usuarios(rol);
CREATE INDEX IF NOT EXISTS idx_usuarios_ultima_actividad ON usuarios(ultima_actividad);