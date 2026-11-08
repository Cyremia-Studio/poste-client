# =============================================================================
#  Cyremia : préparer un PC Windows pour faire évoluer son site avec Claude Code
# =============================================================================
#
#  Pour le client, une seule ligne à copier-coller dans PowerShell
#  (menu Démarrer, taper « PowerShell », ouvrir « Windows PowerShell ») :
#
#    irm https://poste.cyremia.cloud/windows | iex
#
#  Même parcours que la version Mac (installer.sh), en 7 étapes, relançable sans risque :
#  affichage (gum), Git, GitHub CLI, application Claude, connexion GitHub, projet dans
#  %USERPROFILE%\code, puis ouverture de l'application Claude.
#
#  Il ne crée aucun compte, ne lit et n'écrit aucun mot de passe.
#  Compatible Windows PowerShell 5.1 et PowerShell 7.
#
#  Réglages réservés à Cyremia (tests) : variables d'environnement
#    CYREMIA_DOSSIER_CODE, CYREMIA_DOSSIER_OUTILS, CYREMIA_AUTO=oui
# =============================================================================

& {
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Organisation  = 'Cyremia-Studio'
$DossierCode   = if ($env:CYREMIA_DOSSIER_CODE)   { $env:CYREMIA_DOSSIER_CODE }   else { Join-Path $env:USERPROFILE 'code' }
$DossierOutils = if ($env:CYREMIA_DOSSIER_OUTILS) { $env:CYREMIA_DOSSIER_OUTILS } else { Join-Path $env:USERPROFILE '.local\bin' }
$Auto          = [bool]$env:CYREMIA_AUTO
$Journal       = Join-Path $env:LOCALAPPDATA 'Cyremia\poste-client.log'
$Contact       = 'Cyremia (contact@cyremia.com, 03 62 81 27 80)'
$Etapes        = 7

$GumVersion = '2.0.2'
$GumSha     = '0397091dec9b4e8f00e02b90fd3eb07bf45acabbdb61d67437950f18e03a8b79'
$GhVersion  = '2.103.2'
$GhShaAmd64 = 'fef9fcdd8fdabd0501ab8b3d99eac976f504ab55d01bef9e8ef428a5d900ddda'
$GhShaArm64 = 'cefaaa3efcd110ef7bf71071a2242b85fd3d2ac26d7d62e1082de6a1e60a81d6'

$Temp = Join-Path $env:TEMP ("cyremia-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Temp, $DossierOutils, (Split-Path $Journal) | Out-Null
Add-Content -Path $Journal -Value ("=== {0} : lancement ({1}, {2})" -f (Get-Date -Format 'dd/MM/yyyy HH:mm:ss'), [Environment]::OSVersion.VersionString, $env:PROCESSOR_ARCHITECTURE)

function Noter($texte) { Add-Content -Path $Journal -Value ("{0} {1}" -f (Get-Date -Format 'HH:mm:ss'), $texte) }

function Rafraichir-Path {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = "$DossierOutils;$machine;$user"
}
Rafraichir-Path

function A-Gum { [bool](Get-Command gum -ErrorAction SilentlyContinue) }
function Existe($commande) { [bool](Get-Command $commande -ErrorAction SilentlyContinue) }

# --- Affichage ---------------------------------------------------------------

function Cadre($couleur, [string[]]$lignes) {
  if (A-Gum) { & gum style --border rounded --border-foreground $couleur --padding "1 2" --margin "1 0" @lignes }
  else { Write-Host ''; Write-Host ('-' * 64); $lignes | ForEach-Object { Write-Host "  $_" }; Write-Host ('-' * 64); Write-Host '' }
}
function Etape($n, $titre) {
  Noter "ÉTAPE $n : $titre"
  Write-Host ''
  if (A-Gum) { & gum style --bold --foreground 39 "Étape $n sur $Etapes : $titre" } else { Write-Host "=== Étape $n sur $Etapes : $titre ===" -ForegroundColor Cyan }
}
function Dire($texte)      { if (A-Gum) { & gum style $texte } else { Write-Host $texte } }
function Ok($texte)        { Noter "ok : $texte"; if (A-Gum) { & gum style --foreground 42 "✓ $texte" } else { Write-Host "[OK] $texte" -ForegroundColor Green } }
function Attention($texte) { Noter "attention : $texte"; if (A-Gum) { & gum style --foreground 214 "! $texte" } else { Write-Host "[!] $texte" -ForegroundColor Yellow } }

function Echec($quoi, $faire) {
  Noter "ÉCHEC : $quoi"
  $lignes = @("Quelque chose n'a pas marché.", '', $quoi, '', "Que faire : $faire", '',
              "Si ça bloque encore, prévenez $Contact, en lui envoyant ce fichier :", $Journal)
  if (A-Gum) { & gum style --border rounded --border-foreground 196 --padding "1 2" --width 70 @lignes }
  else { $lignes | ForEach-Object { Write-Host $_ -ForegroundColor Red } }
  Remove-Item -Recurse -Force $Temp -ErrorAction SilentlyContinue
  throw 'arret-cyremia'
}

function Question($texte) {
  if ($Auto) { Noter "question auto (oui) : $texte"; return $true }
  if (A-Gum) { & gum confirm --affirmative 'Oui' --negative 'Non' $texte; return ($LASTEXITCODE -eq 0) }
  $r = Read-Host "$texte [o/n]"; return ($r -eq '' -or $r -match '^(o|oui)$')
}
function Pause-Cyremia {
  if ($Auto) { return }
  if (A-Gum) { & gum style --faint 'Appuyez sur Entrée pour continuer…' } else { Write-Host 'Appuyez sur Entrée pour continuer…' }
  [void](Read-Host)
}

# Lance un programme en affichant une animation ; la sortie va dans le journal.
function Patienter($titre, $programme, [string[]]$arguments) {
  Noter "commande : $programme $($arguments -join ' ')"
  if (A-Gum) {
    $journalEchappe = $Journal -replace "'", "''"
    $script = "& '$programme' $(($arguments | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ' ') *>> '$journalEchappe'; exit `$LASTEXITCODE"
    & gum spin --spinner dot --spinner.foreground 39 --title " $titre" -- powershell -NoProfile -ExecutionPolicy Bypass -Command $script
  } else {
    Write-Host "… $titre"; & $programme @arguments *>> $Journal
  }
  return ($LASTEXITCODE -eq 0)
}

function Telecharger-Verifie($url, $fichier, $sha) {
  try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $fichier } catch { Noter "téléchargement échoué : $url"; return $false }
  $calcule = (Get-FileHash -Algorithm SHA256 $fichier).Hash.ToLower()
  if ($calcule -ne $sha) { Noter "empreinte inattendue pour $url : $calcule"; return $false }
  return $true
}

# --- Vérifications de départ -------------------------------------------------

$arch = $env:PROCESSOR_ARCHITECTURE
if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
$GhArch = if ($arch -eq 'ARM64') { 'arm64' } else { 'amd64' }
$GhSha  = if ($arch -eq 'ARM64') { $GhShaArm64 } else { $GhShaAmd64 }

# --- Étape 1 : affichage -----------------------------------------------------

Write-Host ''
Write-Host 'Bonjour ! Nous préparons votre ordinateur. Un instant, on installe d''abord l''affichage…'
Etape 1 "l'affichage"
$gumVersionOk = (A-Gum) -and ((& gum --version 2>$null) -match "v$GumVersion")
if ($gumVersionOk) { Ok "L'affichage est déjà en place." }
else {
  $zip = Join-Path $Temp 'gum.zip'
  if (Telecharger-Verifie "https://github.com/charmbracelet/gum/releases/download/v$GumVersion/gum_${GumVersion}_Windows_x86_64.zip" $zip $GumSha) {
    Expand-Archive -Force -Path $zip -DestinationPath $Temp
    $exe = Get-ChildItem -Path $Temp -Recurse -Filter 'gum.exe' | Select-Object -First 1
    if ($exe) { Copy-Item -Force $exe.FullName (Join-Path $DossierOutils 'gum.exe'); Ok "L'affichage est installé." }
  }
  if (-not (A-Gum)) { Write-Host "(L'affichage amélioré n'a pas pu être installé : on continue en mode simple, tout fonctionne quand même.)" }
}

Cadre 39 @(
  'Bienvenue ! Ce programme prépare votre ordinateur',
  'pour que vous puissiez faire évoluer votre site vous-même,',
  'en parlant à Claude Code.',
  '',
  'Ce qui va se passer, en 10 à 20 minutes :',
  "  • installation d'outils gratuits (Git, GitHub, application Claude) ;",
  '  • connexion à votre compte GitHub, dans votre navigateur ;',
  '  • récupération de votre site dans le dossier « code » ;',
  "  • ouverture de l'application Claude, prête à travailler.",
  '',
  "Rien n'est supprimé sur votre ordinateur.",
  'Windows peut vous demander une autorisation (« Oui »),',
  'mais aucun mot de passe ne vous sera demandé ici.',
  'En cas d''interruption, relancez simplement la même ligne.'
)
if (-not (Question 'On commence ?')) { Dire "D'accord, rien n'a été modifié. Relancez la ligne quand vous voulez."; return }

try {

# --- Étape 2 : Git -----------------------------------------------------------

Etape 2 'Git'
if (Existe git) { Ok "Git est déjà installé ($((& git --version) -replace 'git version ',''))." }
else {
  if (-not (Existe winget)) {
    Echec "L'installateur de Windows (winget) est absent de cet ordinateur." `
          "ouvrez le Microsoft Store, installez « Programme d'installation d'application », puis relancez la même ligne."
  }
  Cadre 214 @(
    'Installation de Git.',
    '',
    'Si Windows affiche « Voulez-vous autoriser cette application',
    'à apporter des modifications ? », cliquez sur « Oui ».'
  )
  [void](Patienter 'Installation de Git (2 à 5 minutes)…' 'winget' @('install','--id','Git.Git','-e','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent'))
  Rafraichir-Path
  if (-not (Existe git)) {
    $gitParDefaut = Join-Path $env:ProgramFiles 'Git\cmd'
    if (Test-Path (Join-Path $gitParDefaut 'git.exe')) { $env:Path = "$gitParDefaut;$env:Path" }
  }
  if (Existe git) { Ok 'Git est installé.' }
  else { Echec "Git n'a pas pu être installé." "relancez la même ligne et répondez « Oui » si Windows demande une autorisation." }
}

# --- Étape 3 : GitHub CLI ----------------------------------------------------

Etape 3 "l'outil GitHub"
if (Existe gh) { Ok "L'outil GitHub est déjà installé." }
else {
  $zip = Join-Path $Temp 'gh.zip'
  Dire "… Téléchargement de l'outil GitHub"
  if (-not (Telecharger-Verifie "https://github.com/cli/cli/releases/download/v$GhVersion/gh_${GhVersion}_windows_$GhArch.zip" $zip $GhSha)) {
    Echec "Le téléchargement de l'outil GitHub est incomplet ou n'est pas celui attendu." 'vérifiez votre connexion Internet, puis relancez la même ligne.'
  }
  $dest = Join-Path $Temp 'gh'
  Expand-Archive -Force -Path $zip -DestinationPath $dest
  Copy-Item -Force (Join-Path $dest 'bin\gh.exe') (Join-Path $DossierOutils 'gh.exe')
  if (Existe gh) { Ok "L'outil GitHub est installé." } else { Echec "L'outil GitHub n'a pas pu être installé." 'relancez la même ligne.' }
}

# --- Étape 4 : l'application Claude -----------------------------------------

function App-Claude {
  $chemins = @((Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'),
               (Join-Path $env:LOCALAPPDATA 'Programs\Claude\Claude.exe'),
               (Join-Path $env:ProgramFiles 'Claude\Claude.exe'))
  foreach ($c in $chemins) { if (Test-Path $c) { return $c } }
  $raccourciMenu = Get-ChildItem -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs') -Recurse -Filter 'Claude*.lnk' -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($raccourciMenu) { return $raccourciMenu.FullName }
  return $null
}

Etape 4 "l'application Claude"
if (App-Claude) { Ok "L'application Claude est déjà installée." }
elseif ($Auto) { Attention 'Application Claude absente (mode test : on continue).' }
else {
  if (Existe winget) {
    [void](Patienter "Installation de l'application Claude…" 'winget' @('install','--id','Anthropic.Claude','-e','--source','winget','--accept-package-agreements','--accept-source-agreements','--silent'))
  }
  if (-not (App-Claude)) {
    Cadre 214 @(
      "Installons l'application Claude, celle où vous parlerez à Claude Code.",
      '',
      '  1. Appuyez sur Entrée : la page de téléchargement s''ouvre.',
      '  2. Cliquez sur « Download for Windows » (ou « Télécharger »).',
      '  3. Ouvrez le fichier téléchargé et suivez l''installation.',
      '',
      'Revenez ici ensuite : le programme reprend tout seul.'
    )
    Pause-Cyremia
    Start-Process 'https://claude.com/download'
    Dire "… En attente de l'installation de l'application Claude"
    $n = 0
    while (-not (App-Claude) -and $n -lt 600) { Start-Sleep -Seconds 3; $n++ }
  }
  if (App-Claude) { Ok "L'application Claude est installée." }
  else { Echec "L'application Claude n'a pas été trouvée sur cet ordinateur." 'terminez son installation, puis relancez la même ligne.' }
}

# Rendre les outils disponibles dans les prochaines fenêtres
if (-not $Auto) {
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  if (-not ($userPath -split ';' | Where-Object { $_ -eq $DossierOutils })) {
    [Environment]::SetEnvironmentVariable('Path', ($DossierOutils + ';' + $userPath).TrimEnd(';'), 'User')
    Noter "PATH utilisateur complété avec $DossierOutils"
  }
}

# --- Étape 5 : connexion à GitHub --------------------------------------------

Etape 5 'la connexion à votre compte GitHub'
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -eq 0) {
  $identifiant = & gh api user --jq .login 2>$null
  Ok "Vous êtes déjà connecté à GitHub sous le nom « $identifiant »."
  if (-not (Question 'Est-ce bien votre compte GitHub ?')) {
    'Y' | & gh auth logout --hostname github.com *>> $Journal
    Attention 'Compte déconnecté. On vous reconnecte avec le bon compte.'
  }
}
& gh auth status --hostname github.com *> $null
if ($LASTEXITCODE -ne 0) {
  Cadre 214 @(
    'Nous allons relier cet ordinateur à votre compte GitHub.',
    '',
    "  1. Un code de 8 caractères va s'afficher (exemple : ABCD-1234).",
    '     Il est déjà copié pour vous.',
    "  2. Appuyez sur Entrée : votre navigateur s'ouvre sur GitHub.",
    '  3. Connectez-vous si besoin, collez le code (Ctrl + V),',
    '     puis cliquez sur « Continue », puis sur « Authorize github ».',
    '  4. Revenez ici : la suite démarre toute seule.'
  )
  Pause-Cyremia
  & gh auth login --hostname github.com --git-protocol https --web --clipboard --skip-ssh-key
  if ($LASTEXITCODE -ne 0) { Echec "La connexion à GitHub n'a pas abouti." 'relancez la même ligne et suivez les quatre étapes du cadre orange.' }
}
& gh auth setup-git --hostname github.com *>> $Journal
$identifiant = & gh api user --jq .login 2>$null
if (-not $identifiant) { Echec 'Impossible de lire votre compte GitHub.' 'relancez la même ligne.' }
Ok "Connecté à GitHub sous le nom « $identifiant »."

if (-not (& git config --global user.name 2>$null)) {
  $nomAffiche = & gh api user --jq '.name // .login' 2>$null
  & git config --global user.name $(if ($nomAffiche) { $nomAffiche } else { $identifiant })
}
if (-not (& git config --global user.email 2>$null)) {
  $moi = (& gh api user) -join "`n" | ConvertFrom-Json
  & git config --global user.email ("{0}+{1}@users.noreply.github.com" -f $moi.id, $moi.login)
}

# --- Étape 6 : votre projet --------------------------------------------------

Etape 6 'votre projet'
$invitations = @()
try { $invitations = @((& gh api user/repository_invitations 2>>$Journal) -join "`n" | ConvertFrom-Json) } catch { }
foreach ($invitation in @($invitations | Where-Object { $_ -and $_.repository.owner.login -eq $Organisation })) {
  $id = $invitation.id; $nomDepot = $invitation.repository.name
  & gh api -X PATCH "user/repository_invitations/$id" *>> $Journal
  if ($LASTEXITCODE -eq 0) { Ok "Invitation de Cyremia acceptée pour « $nomDepot »." }
  else { Attention "L'invitation pour « $nomDepot » n'a pas pu être acceptée automatiquement." }
}

$depots = @()
try { $depots = @((& gh api 'user/repos?affiliation=collaborator,organization_member&per_page=100' 2>>$Journal) -join "`n" | ConvertFrom-Json) } catch { }
$projets = @($depots | Where-Object { $_ -and $_.owner.login -eq $Organisation } | ForEach-Object { $_.name } | Sort-Object -Unique)
if ($projets.Count -eq 0) {
  Echec "Aucun projet Cyremia n'est encore relié à votre compte GitHub « $identifiant »." `
        "donnez à Cyremia votre identifiant GitHub ( $identifiant ), attendez son invitation, puis relancez la même ligne."
} elseif ($projets.Count -eq 1 -or $Auto) {
  $projet = $projets[0]
} else {
  Dire 'Plusieurs projets sont reliés à votre compte. Lequel voulez-vous ouvrir ?'
  if (A-Gum) { $projet = $projets | & gum choose --header 'Utilisez les flèches, puis Entrée' }
  else { for ($i = 0; $i -lt $projets.Count; $i++) { Write-Host "  $($i + 1). $($projets[$i])" }; $projet = $projets[[int](Read-Host 'Numéro') - 1] }
  if (-not $projet) { Echec 'Aucun projet choisi.' 'relancez la même ligne et choisissez un projet.' }
}
Ok "Votre projet : $projet"

$dossierProjet = Join-Path $DossierCode $projet
New-Item -ItemType Directory -Force -Path $DossierCode | Out-Null
if (Test-Path (Join-Path $dossierProjet '.git')) {
  if (& git -C $dossierProjet status --porcelain 2>$null) {
    Attention "Votre dossier contient des modifications pas encore envoyées : on n'y touche pas."
    Dire "Ouvrez Claude Code et dites-lui : « Enregistre et envoie mes modifications sur l'aperçu »."
  } elseif (Patienter 'Mise à jour de votre projet…' 'git' @('-C', $dossierProjet, 'pull', '--ff-only')) {
    Ok "Votre projet est à jour dans : $dossierProjet"
  } else {
    Attention "La mise à jour automatique n'a pas pu se faire. Claude Code saura la terminer avec vous."
  }
} elseif (Test-Path $dossierProjet) {
  Echec "Un dossier « $projet » existe déjà dans « code » mais n'est pas un projet relié à GitHub." `
        "renommez ou déplacez ce dossier (par exemple « $projet ancien »), puis relancez la même ligne."
} else {
  if (-not (Patienter 'Récupération de votre projet…' 'gh' @('repo', 'clone', "$Organisation/$projet", $dossierProjet))) {
    Echec "Votre projet n'a pas pu être récupéré." 'vérifiez votre connexion Internet, puis relancez la même ligne.'
  }
  Ok "Votre projet est dans : $dossierProjet"
}

$nomProjet = $projet; $apercu = ''
$fichierInfos = Join-Path $dossierProjet 'cyremia.json'
if (Test-Path $fichierInfos) {
  try { $infos = Get-Content -Raw -Encoding UTF8 $fichierInfos | ConvertFrom-Json; if ($infos.nom) { $nomProjet = $infos.nom }; $apercu = $infos.apercu } catch { }
}

# --- Étape 7 : ouvrir le projet dans l'application Claude -------------------

Etape 7 "ouvrir votre site dans l'application Claude"
$fin = @("C'est prêt !", '', 'Votre site est sur votre ordinateur, dans le dossier :', "  code > $projet")
if ($apercu) { $fin += "Votre aperçu en ligne : $apercu" }
$fin += @('', "Pour travailler sur votre site, dans l'application Claude :",
          '  1. Ouvrez Claude et connectez-vous à VOTRE compte Claude.',
          '  2. Allez dans l''onglet « Code ».',
          '  3. Choisissez le dossier de votre site :',
          "     dossier personnel > code > $projet",
          '  4. Écrivez simplement ce que vous voulez changer.', '',
          'La prochaine fois, votre site apparaîtra dans la liste des',
          'projets récents de l''onglet Code.')
Cadre 42 $fin
Noter "terminé : $dossierProjet"

if (-not $Auto -and (Question "Ouvrir l'application Claude et le dossier de votre site maintenant ?")) {
  Start-Process explorer.exe $dossierProjet
  $app = App-Claude
  if ($app) { Start-Process $app } else { Attention "Ouvrez l'application Claude depuis le menu Démarrer." }
}
Dire 'À bientôt ! Vous pouvez fermer cette fenêtre.'

} catch {
  if ($_.Exception.Message -ne 'arret-cyremia') {
    Noter "erreur inattendue : $($_.Exception.Message)"
    Write-Host "Erreur inattendue : $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Prévenez $Contact en envoyant ce fichier : $Journal"
  }
} finally {
  Remove-Item -Recurse -Force $Temp -ErrorAction SilentlyContinue
}
}
