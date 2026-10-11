# Scripts

PowerShell 5.1+, run as a domain admin on a machine with the ActiveDirectory module.
Both write one line per action to `Z:\logs\jml.log`: `date | who ran it | ALTA or BAJA | ticket | what happened`.

```powershell
.\New-BretemaUser.ps1     -Nombre Sofía -Apellido Núñez -Departamento Administracion -Ticket RRHH-010
.\Disable-BretemaUser.ps1 -Usuario sofia.nunez -Ticket RRHH-011
```

Saved as UTF-8 with BOM (the comments contain accents). Design decisions and the test table are in the [main write-up](../README.md).
