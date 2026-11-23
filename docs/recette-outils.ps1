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
