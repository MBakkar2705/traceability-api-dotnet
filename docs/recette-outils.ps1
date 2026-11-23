# recette-outils.ps1
# Helper functions for the functional acceptance notebook (docs/recette.md).
# Load them in a PowerShell window with:   . .\docs\recette-outils.ps1
# Rules:
# - No password and no token is ever written in this file or printed by a function.
# - A password is typed in a masked prompt. The token stays in $global:Token and lives 300 s.
# - ASCII only: Windows PowerShell 5.1 may misread accents in a file without BOM.

# ============================== Authentication ==============================

# Get-Trial: asks Keycloak for a token for a test account and keeps it in $global:Token.
# Prints only the HTTP code, the token type and expires_in. Usage: Get-Trial reader-test
function Get-Trial($User, $Base = 'http://localhost:8180') {
  $pw = [Net.NetworkCredential]::new('', (Read-Host "Password for $User" -AsSecureString)).Password
  $r = curl.exe -s -w "`n%{http_code}" -d "grant_type=password&client_id=traceability-trial&username=$User&password=$([uri]::EscapeDataString($pw))" "$Base/realms/traceability/protocol/openid-connect/token"
  $code = $r[-1]
  if ($code -eq '200') {
    $j = $r[0] | ConvertFrom-Json
    $global:Token = $j.access_token
    "HTTP $code $($j.token_type) expires_in $($j.expires_in)"
  } else { "HTTP $code" }
}

# Show-Token: prints the issuer, audience, client, lifetime and roles of $global:Token.
# Never prints the token itself.
function Show-Token {
  $p = $global:Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
  $p = $p.PadRight($p.Length + (4 - $p.Length % 4) % 4, '=')
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  [pscustomobject]@{
    iss = $c.iss; aud = ($c.aud -join ','); azp = $c.azp
    exp_moins_iat = $c.exp - $c.iat
    exp_utc = [DateTimeOffset]::FromUnixTimeSeconds($c.exp).UtcDateTime.ToString('HH:mm:ss')
    roles = ($c.realm_access.roles -join ',')
  } | Format-List
}

# Show-Identity: prints who the token says the user is (sub, preferred_username, roles).
function Show-Identity {
  $p = $global:Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
  $p = $p.PadRight($p.Length + (4 - $p.Length % 4) % 4, '=')
  $c = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($p)) | ConvertFrom-Json
  [pscustomobject]@{ sub = $c.sub; preferred_username = $c.preferred_username; roles = ($c.realm_access.roles -join ',') } | Format-List
}

# ================================ Reading ===================================

# Base address of the API (the API window must be running).
$global:Api = 'https://localhost:7080'

# Read-Api: GET on a path of the API, with the token kept in $global:Token.
# Prints the HTTP code, a hint for 000, 401 and 403, then the body as indented JSON.
# Never prints the token. Usage: Read-Api '/farms'    Read-Api '/batches?pageSize=5'
function Read-Api($Path) {
  $out = @(curl.exe -s --ssl-no-revoke -w "`n%{http_code}" -H "Authorization: Bearer $global:Token" "$global:Api$Path")
  $code = $out[-1]
  $body = ($out[0..($out.Count - 2)] -join "`n").Trim()
  "HTTP $code"
  if ($code -eq '000') { '000: the API does not answer. Is it running?' }
  if ($code -eq '401') { '401: token missing, expired (300 s) or not accepted. Run Get-Trial again.' }
  if ($code -eq '403') { '403: this account is not allowed to do this.' }
  if ($body) {
    try { $body | ConvertFrom-Json | ConvertTo-Json -Depth 10 } catch { $body }
  }
}

# Read-Lot: shows the sheet of one batch (GET /batches/{code}). Usage: Read-Lot 'R01-ORDRE-261123'
function Read-Lot($Code) { Read-Api "/batches/$([uri]::EscapeDataString($Code))" }

# ================================ Writing ===================================

# Send-Api: POST on a path of the API, with the token kept in $global:Token.
# $Body is either a hashtable (turned into JSON) or a text sent as it is (to try a wrong or
# incomplete body). Prints the HTTP code, a hint for 000, 401 and 403, then the body if any.
# Never prints the token. Dates are given as text ('2026-11-23T06:00:00Z'), quantities as numbers.
function Send-Api($Path, $Body) {
  $json = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Compress }
  $tmp = [IO.Path]::GetTempFileName()
  try {
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding($false)))
    $out = @(curl.exe -s --ssl-no-revoke -X POST -w "`n%{http_code}" -H "Authorization: Bearer $global:Token" -H "Content-Type: application/json" --data-binary "@$tmp" "$global:Api$Path")
  } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
  $code = $out[-1]
  $resp = ($out[0..($out.Count - 2)] -join "`n").Trim()
  "HTTP $code"
  if ($code -eq '000') { '000: the API does not answer. Is it running?' }
  if ($code -eq '401') { '401: token missing, expired (300 s) or not accepted. Run Get-Trial again.' }
  if ($code -eq '403') { '403: this account is not allowed to do this.' }
  if ($resp) {
    try { $resp | ConvertFrom-Json | ConvertTo-Json -Depth 10 } catch { $resp }
  }
}

# New-Farm: POST /farms. Usage: New-Farm 'FERME-NORD' 'Ferme du Nord' 'Nord'
function New-Farm($Code, $Name, $Region) {
  Send-Api '/farms' ([ordered]@{ code = $Code; name = $Name; region = $Region })
}

# New-Station: POST /stations. Usage: New-Station 'STA-RECEPTION' 'Station de reception'
function New-Station($Code, $Name) {
  Send-Api '/stations' ([ordered]@{ code = $Code; name = $Name })
}

# Add-Capability: POST /stations/{code}/capabilities (RECEPTION, SORTING, PACKING or SHIPMENT).
function Add-Capability($Station, $Type) {
  Send-Api "/stations/$([uri]::EscapeDataString($Station))/capabilities" ([ordered]@{ movementType = $Type })
}

# New-Lot: POST /batches (creates the batch and its reception).
# Usage: New-Lot 'R01-ORDRE-261123' 'FERME-NORD' 'Roma' '2026-11-22' 100.5 'STA-RECEPTION' '2026-11-23T06:00:00Z'
function New-Lot($Code, $Farm, $Variety, $Harvest, $Kg, $Station, $At) {
  Send-Api '/batches' ([ordered]@{ batchCode = $Code; farmCode = $Farm; variety = $Variety; harvestDate = $Harvest; quantityKg = $Kg; stationCode = $Station; occurredAt = $At })
}

# Add-Movement: POST /batches/{code}/movements (SORTING, then PACKING, then SHIPMENT).
function Add-Movement($Code, $Station, $Type, $Kg, $At) {
  Send-Api "/batches/$([uri]::EscapeDataString($Code))/movements" ([ordered]@{ stationCode = $Station; movementType = $Type; quantityKg = $Kg; occurredAt = $At })
}
