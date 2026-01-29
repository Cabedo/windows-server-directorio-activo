<#
.SYNOPSIS
  Script de creación de estructura de Active Directory a partir de CSV.

.DESCRIPTION
  Crea en el dominio empresa.local:
  - OU raíz: Empresa
  - OU por cada departamento del archivo departamentos.csv
  - Grupo de seguridad GLOBAL por departamento (mismo nombre del departamento)
  - Usuarios desde empleados.csv (login nombre.apellido)
    * Password por defecto: aso2025.
    * Obliga a cambiar password en el siguiente inicio de sesión
  - Cada usuario se añade al grupo de su departamento.

.FILES
  - departamentos.csv (departamento;descripcion)
  - empleados.csv     (departamento;nombre;apellido)

.NOTES
  Ejecutar como Administrador en el DC (o equipo con RSAT) con permisos suficientes.
#>

param(
  [string] $DomainFqdn = "empresa.local",
  [string] $DepartamentosCsv = ".\departamentos.csv",
  [string] $EmpleadosCsv = ".\empleados.csv",
  [char]   $Delimiter = ';',
  [string] $RootOUName = "Empresa",
  [string] $DefaultPasswordPlain = "aso2025."
)

# -----------------------------
# FUNCIONES AUXILIARES
# -----------------------------

function Convert-FqdnToDn {
  param([Parameter(Mandatory=$true)][string]$Fqdn)
  return ($Fqdn.Split('.') | ForEach-Object { "DC=$_" }) -join ','
}

function Remove-Diacritics {
  param([Parameter(Mandatory=$true)][string]$Text)
  $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $normalized.ToCharArray()) {
    $cat = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
      [void]$sb.Append($ch)
    }
  }
  return $sb.ToString().Normalize([Text.NormalizationForm]::FormC)
}

function New-BaseLogin {
  param(
    [Parameter(Mandatory=$true)][string]$Nombre,
    [Parameter(Mandatory=$true)][string]$Apellido
  )

  $n = (Remove-Diacritics $Nombre).Trim().ToLower() -replace '\s+', ''
  $a = (Remove-Diacritics $Apellido).Trim().ToLower() -replace '\s+', ''

  $n = $n -replace '[^a-z0-9\.-]', ''
  $a = $a -replace '[^a-z0-9\.-]', ''

  return "$n.$a"
}

function Get-UniqueLogin {
  param([Parameter(Mandatory=$true)][string]$BaseLogin)

  $login = $BaseLogin
  $i = 2
  while (Get-ADUser -Filter "SamAccountName -eq '$login'" -ErrorAction SilentlyContinue) {
    $login = "$BaseLogin$i"
    $i++
  }
  return $login
}

function Ensure-OU {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$Path
  )

  $ouDn = "OU=$Name,$Path"
  $exists = Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$ouDn)" -ErrorAction SilentlyContinue
  if (-not $exists) {
    New-ADOrganizationalUnit -Name $Name -Path $Path -ProtectedFromAccidentalDeletion $false | Out-Null
    Write-Host "OK: OU creada -> $ouDn"
  } else {
    Write-Host "OK: OU ya existe -> $ouDn"
  }
  return $ouDn
}

function Ensure-Group {
  param(
    [Parameter(Mandatory=$true)][string]$Name,
    [Parameter(Mandatory=$true)][string]$PathOuDn,
    [Parameter(Mandatory=$false)][string]$Description = ""
  )

  $group = Get-ADGroup -Filter "SamAccountName -eq '$Name'" -SearchBase $PathOuDn -ErrorAction SilentlyContinue
  if (-not $group) {
    New-ADGroup -Name $Name -SamAccountName $Name -GroupScope Global -GroupCategory Security -Path $PathOuDn -Description $Description | Out-Null
    Write-Host "OK: Grupo GLOBAL creado -> $Name"
  } else {
    Write-Host "OK: Grupo ya existe -> $Name"
  }
}

function Ensure-User {
  param(
    [Parameter(Mandatory=$true)][string]$Login,
    [Parameter(Mandatory=$true)][string]$Nombre,
    [Parameter(Mandatory=$true)][string]$Apellido,
    [Parameter(Mandatory=$true)][string]$OuDn,
    [Parameter(Mandatory=$true)][string]$UpnSuffix,
    [Parameter(Mandatory=$true)][securestring]$DefaultPassword
  )

  $displayName = "$Nombre $Apellido"
  $upn = "$Login@$UpnSuffix"

  New-ADUser `
    -Name $displayName `
    -GivenName $Nombre `
    -Surname $Apellido `
    -DisplayName $displayName `
    -SamAccountName $Login `
    -UserPrincipalName $upn `
    -Path $OuDn `
    -AccountPassword $DefaultPassword `
    -Enabled $true `
    -ChangePasswordAtLogon $true | Out-Null

  Write-Host "OK: Usuario creado -> $Login"
}

# -----------------------------
# EJECUCIÓN PRINCIPAL
# -----------------------------

Import-Module ActiveDirectory -ErrorAction Stop

if (-not (Test-Path $DepartamentosCsv)) { throw "No existe: $DepartamentosCsv" }
if (-not (Test-Path $EmpleadosCsv))     { throw "No existe: $EmpleadosCsv" }

$domainDn = Convert-FqdnToDn -Fqdn $DomainFqdn
$rootOuDn = Ensure-OU -Name $RootOUName -Path $domainDn

$defaultPassword = ConvertTo-SecureString $DefaultPasswordPlain -AsPlainText -Force

$departamentos = Import-Csv -Path $DepartamentosCsv -Delimiter $Delimiter
$empleados     = Import-Csv -Path $EmpleadosCsv -Delimiter $Delimiter

# Crear OUs y grupos
$deptOuMap = @{}

foreach ($d in $departamentos) {
  $dept = ($d.departamento).Trim()
  $desc = ($d.descripcion).Trim()

  if ([string]::IsNullOrWhiteSpace($dept)) { continue }

  $deptOuDn = Ensure-OU -Name $dept -Path $rootOuDn
  $deptOuMap[$dept] = $deptOuDn

  Ensure-Group -Name $dept -PathOuDn $deptOuDn -Description $desc
}

# Crear usuarios y añadir a grupos
foreach ($e in $empleados) {
  $dept     = ($e.departamento).Trim()
  $nombre   = ($e.nombre).Trim()
  $apellido = ($e.apellido).Trim()

  if (-not $deptOuMap.ContainsKey($dept)) {
    Write-Warning "Departamento '$dept' no definido. Usuario omitido: $nombre $apellido"
    continue
  }

  $ouDn = $deptOuMap[$dept]

  $baseLogin = New-BaseLogin -Nombre $nombre -Apellido $apellido
  $login = Get-UniqueLogin -BaseLogin $baseLogin

  if (-not (Get-ADUser -Filter "SamAccountName -eq '$login'" -ErrorAction SilentlyContinue)) {
    Ensure-User -Login $login -Nombre $nombre -Apellido $apellido -OuDn $ouDn -UpnSuffix $DomainFqdn -DefaultPassword $defaultPassword
  }

  try {
    Add-ADGroupMember -Identity $dept -Members $login -ErrorAction Stop
    Write-Host "OK: $login añadido al grupo $dept"
  } catch {
    Write-Warning "No se pudo añadir $login al grupo $dept"
  }
}

Write-Host "`nFIN: Estructura de Active Directory creada correctamente."
