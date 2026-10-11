param(
    [Parameter(Mandatory)]
    [string]$Usuario,

    [Parameter(Mandatory)]
    [string]$Ticket
)

# Leaver script. It disables, it does NOT delete: the account is kept (in the Bajas OU) for the
# retention period. Every part checks the current state first, so running it twice changes nothing.

$log = "Z:\logs\jml.log"
function Write-Log([string]$message) {
    $line = "{0} | {1} | BAJA | {2} | {3}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $env:USERNAME, $Ticket, $message
    Add-Content -Path $log -Value $line
}

# Part 1: find the account (with its groups, used in part 4)
$cuenta = Get-ADUser -Filter "SamAccountName -eq '$Usuario'" -Properties MemberOf
if (-not $cuenta) {
    Write-Log "ERROR: $Usuario does not exist. Nothing done."
    throw "$Usuario does not exist in AD."
}
Write-Host "Found: $($cuenta.Name) | SID $($cuenta.SID) | enabled: $($cuenta.Enabled)"

# Part 2: this script NEVER offboards privileged accounts (those go by hand, with another process).
# -Recursive also catches nested membership; comparing by SID, not by name.
$gruposProtegidos = @("Domain Admins", "Enterprise Admins", "Schema Admins", "T0-Admins")
foreach ($g in $gruposProtegidos) {
    $esMiembro = Get-ADGroupMember -Identity $g -Recursive | Where-Object { $_.SID -eq $cuenta.SID }
    if ($esMiembro) {
        Write-Log "REFUSED: $Usuario is a member of $g (direct or nested). Not touched."
        throw "$Usuario is a privileged account ($g). Admin offboarding is done by hand."
    }
}
# Second, independent signal (defence in depth): the Tier 0 OU
if ($cuenta.DistinguishedName -like "*OU=Tier0,*") {
    Write-Log "REFUSED: $Usuario is in the Tier0 OU. Not touched."
    throw "$Usuario is in Tier0. Admin offboarding is done by hand."
}

# Part 3: DISABLE FIRST (cuts new sign-ins at once; if anything fails later, the state is safe)
if ($cuenta.Enabled) {
    try {
        Disable-ADAccount -Identity $cuenta -ErrorAction Stop
    }
    catch {
        $motivo = $_.Exception.Message
        Write-Log "ERROR disabling $Usuario. Reason: $motivo. Stopping."
        throw "Could not disable $Usuario. Reason: $motivo"
    }
    Write-Host "$Usuario disabled."
    Write-Log "$Usuario disabled. SID $($cuenta.SID)."
} else {
    Write-Host "$Usuario was already disabled."
    Write-Log "$Usuario was already disabled. SID $($cuenta.SID)."
}

# Part 4: record the groups BEFORE removing them (in case HR made a mistake and they must be restored)
$gruposCuenta = $cuenta.MemberOf
if ($gruposCuenta) {
    $nombres = ($gruposCuenta | ForEach-Object { (Get-ADGroup $_).Name }) -join ", "
    Write-Log "Groups of $Usuario before offboarding: $nombres"
    try {
        foreach ($g in $gruposCuenta) {
            Remove-ADGroupMember -Identity $g -Members $cuenta -Confirm:$false -ErrorAction Stop
        }
    }
    catch {
        $motivo = $_.Exception.Message
        Write-Log "ERROR removing groups from $Usuario. Reason: $motivo. The account is ALREADY disabled."
        throw "Could not remove all groups from $Usuario. Reason: $motivo"
    }
    Write-Host "Removed groups of ${Usuario}: $nombres"
    Write-Log "Removed groups of ${Usuario}: $nombres"
} else {
    Write-Host "$Usuario had no groups to remove."
    Write-Log "$Usuario had no groups to remove."
}

# Part 5: move to the Bajas OU (outside the Tiers: no policy of the old tier applies any more)
$ouBajas = "OU=Bajas,OU=Bretema,DC=corp,DC=lab"
if ($cuenta.DistinguishedName -like "*,$ouBajas") {
    Write-Host "$Usuario was already in Bajas."
    Write-Log "$Usuario was already in Bajas."
} else {
    try {
        Move-ADObject -Identity $cuenta -TargetPath $ouBajas -ErrorAction Stop
    }
    catch {
        $motivo = $_.Exception.Message
        Write-Log "ERROR moving $Usuario to Bajas. Reason: $motivo. The account is ALREADY disabled and has no groups."
        throw "Could not move $Usuario to Bajas. Reason: $motivo"
    }
    Write-Host "$Usuario moved to Bajas."
    Write-Log "$Usuario moved to Bajas. Was in: $($cuenta.DistinguishedName)"
}
