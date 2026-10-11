param(
    [Parameter(Mandatory)]
    [string]$Nombre,

    [Parameter(Mandatory)]
    [string]$Apellido,

    [Parameter(Mandatory)]
    [ValidateSet("Administracion", "Ingenieria", "Produccion")]
    [string]$Departamento,

    [Parameter(Mandatory)]
    [string]$Ticket
)

# Joiner script. Parameters: first name, last name, department, HR ticket.
# Idempotent: it checks the real state before acting, so running it twice changes nothing.

$log = "Z:\logs\jml.log"
function Write-Log([string]$message) {
    $line = "{0} | {1} | ALTA | {2} | {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $env:USERNAME, $Ticket, $message
    Add-Content -Path $log -Value $line
}

# 1. Join first and last name, lowercase
$usuario = "$Nombre.$Apellido".ToLower()

# 2. Strip accents and enyes (a with accent -> a, n with tilde -> n)
$usuario = $usuario.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}', ''

# 3. UPN = username + suffix
$upn = "$usuario@bretemacomp.com"

# Department -> group (role-based access control)
$grupos = @{
    "Administracion" = "GG-Administracion"
    "Ingenieria"     = "GG-Ingenieria"
    "Produccion"     = "GG-Produccion"
}
$grupo = $grupos[$Departamento]

# Check 1: does the user already exist?
$existente = Get-ADUser -Filter "UserPrincipalName -eq '$upn'"

# Check 2: does the group exist?
$grupoAD = Get-ADGroup -Filter "Name -eq '$grupo'"
if (-not $grupoAD) {
    Write-Log "ERROR: group $grupo does not exist. Nothing done for $upn."
    throw "Group $grupo does not exist in AD. Nothing done."
}

if ($existente) {
    if (-not $existente.Enabled) {
        Write-Log "WARNING: $upn exists but is DISABLED. Not touched."
        throw "$upn exists but is DISABLED. Review it by hand before going on."
    }
    Write-Host "$upn already exists and is enabled: not creating it again."
    Write-Log "$upn already existed and is enabled: not created again."
} else {
    # Secure input: the password is never shown, stored in plain text or logged
    $password = Read-Host "Initial password for $upn" -AsSecureString

    try {
        New-ADUser -Name "$Nombre $Apellido" `
            -GivenName $Nombre -Surname $Apellido `
            -SamAccountName $usuario -UserPrincipalName $upn `
            -Path "OU=Usuarios,OU=Tier2,OU=Bretema,DC=corp,DC=lab" `
            -AccountPassword $password `
            -ChangePasswordAtLogon $true `
            -Enabled $true `
            -ErrorAction Stop

        Write-Host "Created $upn in $Departamento"
        Write-Log "Created $upn in $Departamento"
    }
    catch {
        # First thing: save the reason before another command overwrites $_
        $motivo = $_.Exception.Message

        # Roll back: if something was half-created, delete it so no junk is left
        $aMedias = Get-ADUser -Filter "UserPrincipalName -eq '$upn'"
        if ($aMedias) {
            Remove-ADUser -Identity $aMedias -Confirm:$false
        }

        # Log BEFORE the throw: code after a throw never runs
        Write-Log "ERROR creating $upn. Reason: $motivo. What was created has been rolled back."
        throw "Could not create $upn. Reason: $motivo. Nothing was left half-done."
    }
}

# Part 5: make sure the user is in the group (whether just created or already existing)
$miembro = Get-ADGroupMember -Identity $grupo | Where-Object { $_.SamAccountName -eq $usuario }

if ($miembro) {
    Write-Host "$usuario was already in $grupo."
    Write-Log "$usuario was already in $grupo."
} else {
    Add-ADGroupMember -Identity $grupo -Members $usuario -ErrorAction Stop
    Write-Host "$usuario added to $grupo."
    Write-Log "$usuario added to $grupo."
}
