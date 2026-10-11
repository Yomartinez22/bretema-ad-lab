# Script de altas y bajas (JML) · Brétema Componentes S.L.

> Forma parte del [laboratorio de AD de Brétema](lab-overview.es.md). El resumen en inglés está en el [README principal](../README.md).

## En una frase

Dos scripts de PowerShell que dan de **alta** y de **baja** a los empleados de Brétema en Active
Directory a partir de un ticket de RRHH, de forma automática y sencilla, y **seguros**: si algo
falla no dejan nada a medias, y ejecutarlos dos veces no cambia nada.

## Cómo se usa

```powershell
# Alta (pide la contraseña inicial sin mostrarla)
.\New-BretemaUser.ps1 -Nombre Sofía -Apellido Núñez -Departamento Administracion -Ticket RRHH-010

# Baja
.\Disable-BretemaUser.ps1 -Usuario sofia.nunez -Ticket RRHH-011
```

Todo queda en `Z:\logs\jml.log`, una línea por acción:
`fecha | quién lo ejecutó | ALTA o BAJA | ticket | qué pasó`.

## Qué hace

**Alta (`New-BretemaUser.ps1`)**
1. Solo acepta los tres departamentos que existen (`ValidateSet`); otro, y para sin tocar nada.
2. Calcula el usuario (`nombre.apellido`, en minúsculas y sin tildes ni eñes) y el UPN
   (`@bretemacomp.com`). El nombre visible conserva las tildes.
3. Traduce el departamento a su grupo (`GG-Administracion`, `GG-Ingenieria`, `GG-Produccion`).
4. Antes de crear nada comprueba: que el grupo existe en AD, que el usuario no existe ya, y si ya
   existe, si está activo (no hace nada) o desactivado (para y avisa).
5. Pide la contraseña inicial con `-AsSecureString` y obliga a cambiarla en el primer inicio de sesión.
6. Si la creación falla, borra lo que se haya creado a medias y apunta el motivo real.
7. Mete al usuario en su grupo, si no estaba ya.

**Baja (`Disable-BretemaUser.ps1`)**
1. Busca la cuenta; si no existe, para.
2. Se niega a tocar administradores: miembros de Domain Admins, Enterprise Admins, Schema Admins o
   T0-Admins (también anidados, comparando por SID) y cualquier cuenta de la OU Tier0.
3. **Desactiva la cuenta primero.**
4. Apunta en el log sus grupos y se los quita.
5. La mueve a la OU `Bajas`, apuntando dónde estaba.

## Decisiones, y por qué

- **Desactivar en vez de borrar:** quita el acceso a la cuenta mientras se le van quitando los
  grupos; permite conservarla 90 días por si se vuelve a dar de alta; y deja revisar lo que tenía
  a su cargo antes de decidir qué hacer con ello.
- **Rollback en vez de dejar la cuenta a medias:** preferimos que el usuario se cree de una vez y
  no por partes, según va tropezando. Una cuenta creada a medias es mucho más liosa.
- **El ticket como columna fija del log:** así hay trazabilidad y evidencia de cada alta y cada
  baja.
- **Rechazar administradores:** este script es para usuarios normales. Puede llegar un ticket
  falso, y una cuenta con privilegios no se puede dar de baja sin verificarla primero.
- **No reactivar sola una cuenta que vuelve:** tiene que pasar por un proceso de verificación.
- **La contraseña con `-AsSecureString`:** para que no quede registro de la contraseña introducida.

## Cómo lo probé

Cada prueba se predijo antes de ejecutarla.

| # | Prueba | Resultado |
|---|---|---|
| 1 | Alta de un departamento que no existe (`Marketing`) | ✅ rechazada antes de empezar |
| 2 | Alta de Laura, que ya existe, está activa y en su grupo | ✅ no crea nada; dos líneas de log |
| 3 | Alta de Pedro con una contraseña de 8 caracteres | ✅ AD la rechaza, se borra lo creado a medias, el log guarda el motivo real y Pedro no existe |
| 4 | Alta de Pedro con una contraseña válida | ✅ creado y añadido a `GG-Produccion` |
| 5 | Baja de un usuario que no existe | ✅ error y línea de log con su ticket |
| 6 | Baja de `adm0-miglesias` | ✅ rechazada: Domain Admins, por anidamiento a través de T0-Admins |
| 7 | Baja de `Administrator` | ✅ rechazada |
| 8 | Baja de Pedro, dos veces | ✅ desactiva, apunta y quita `GG-Produccion`, mueve a `Bajas`; la 2ª vez no cambia nada |
| 9 | Ciclo completo de Sofía Núñez: alta → baja → vuelve | ✅ `sofia.nunez` creado; baja en 5 pasos; el 2º alta se para porque la cuenta existe desactivada, **sin llegar a pedir la contraseña** |

## Lo que NO cubre

- **El borrado a los 90 días:** hoy se hace a mano; no hay un script que revise ese plazo.
- **Las sesiones abiertas:** desactivar impide los inicios de sesión nuevos, pero no cierra una
  sesión que ya estaba abierta; hay que hacerlo a mano (en Entra, revocando las sesiones).
- **El ticket no se verifica:** es texto libre; no se comprueba que exista de verdad en el sistema
  de RRHH.
- **Colisión de nombres:** si entra una segunda Ana García, el alta encuentra la cuenta de la
  primera y le añade el grupo del departamento nuevo: acumulación de privilegios. En real, la clave
  sería el número de empleado de RRHH (`employeeID`), no el nombre.
- **Mínimo privilegio del propio script:** hoy se ejecuta como administrador del dominio. En
  producción iría con una cuenta de servicio con permisos solo sobre la OU de usuarios y los tres
  grupos.

## Puente a E2: lo mismo en Entra (Lifecycle Workflows)

Resumen tras leer la documentación de Microsoft Learn:

- **Qué lo dispara:** no un ticket escrito a mano, sino un **atributo con fecha que viene de RRHH**
  (`employeeHireDate` para el alta), con un **ámbito** que decide a quién se aplica.
- **Qué hace:** convierte en automáticas las tareas manuales de **Joiner, Mover y Leaver**.
- **Cuáles de mis límites resuelve:** el **borrado tras el plazo** (los 90 días) y el **ticket sin
  verificar**, porque el origen es RRHH y no un texto que escribe cualquiera.

Requiere la licencia **Microsoft Entra ID Governance**.
