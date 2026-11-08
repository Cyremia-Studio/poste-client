#!/bin/bash
# =============================================================================
#  Cyremia : préparer un Mac pour faire évoluer son site avec Claude Code
# =============================================================================
#
#  Pour le client, une seule ligne à copier-coller dans le Terminal :
#
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Cyremia-Studio/poste-client/main/installer.sh)"
#
#  Ce que fait le script, dans l'ordre (on peut le relancer sans risque) :
#    1. installe l'outil d'affichage (gum) ;
#    2. installe les outils de développement d'Apple (Git) s'ils manquent ;
#    3. installe GitHub CLI (gh) ;
#    4. installe l'application Claude (avec Claude Code intégré) ;
#    5. connecte le compte GitHub du client (par le navigateur) ;
#    6. accepte les invitations de Cyremia-Studio et récupère son projet dans ~/code ;
#    7. ouvre l'application Claude et montre comment y choisir le dossier du site.
#
#  Il ne crée aucun compte, ne lit et n'écrit aucun mot de passe, et ne touche
#  qu'aux dossiers ~/code et ~/.local/bin.
#
#  Réglages réservés à Cyremia (tests) :
#    CYREMIA_DOSSIER_CODE=/chemin   autre dossier que ~/code
#    CYREMIA_DOSSIER_OUTILS=/chemin autre dossier que ~/.local/bin pour gum et gh
#    CYREMIA_PROJET=nom-du-depot    choisit ce projet sans poser la question
#    CYREMIA_AUTO=oui               répond « oui » partout, prend le premier projet,
#                                   n'installe pas et n'ouvre pas l'application Claude
# =============================================================================

set -u

ORGANISATION="Cyremia-Studio"
DOSSIER_CODE="${CYREMIA_DOSSIER_CODE:-$HOME/code}"
DOSSIER_OUTILS="${CYREMIA_DOSSIER_OUTILS:-$HOME/.local/bin}"
AUTO="${CYREMIA_AUTO:-}"
JOURNAL="$HOME/Library/Logs/cyremia-poste-client.log"
CONTACT="Cyremia (contact@cyremia.com, 03 62 81 27 80)"

GUM_VERSION="2.0.2"
GUM_SHA_ARM64="4777a69b1170b8db23c95d5889fb32186cfda1a3ac950d339aa17e3513633890"
GUM_SHA_X86_64="5374966c7c7199ea879fcaa525ddc6d447a098d3d35496e430a9a1ef38d30485"
GH_VERSION="2.103.2"
GH_SHA_ARM64="5416000f5d17580a187339e0c4068a01ca5c87f7d4fe6ca64933696f967bc418"
GH_SHA_AMD64="2dc7f1fc4761f96732995f6e4f4c6b4d705f2635da4126620c8b30eaa67b9c98"

ETAPES=7
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
export PATH="$DOSSIER_OUTILS:$PATH"
mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null
echo "=== $(date '+%d/%m/%Y %H:%M:%S') : lancement (macOS $(sw_vers -productVersion 2>/dev/null), $(uname -m))" >> "$JOURNAL"

# -----------------------------------------------------------------------------
#  Affichage : gum si disponible, sinon texte simple
# -----------------------------------------------------------------------------

COULEUR_ACCENT="39"     # bleu
COULEUR_OK="42"         # vert
COULEUR_ATTENTION="214" # orange
COULEUR_ERREUR="196"    # rouge

a_gum() { command -v gum >/dev/null 2>&1; }
noter() { echo "$(date '+%H:%M:%S') $*" >> "$JOURNAL"; }

cadre() { # cadre "couleur" "ligne 1" "ligne 2"...
  local couleur="$1"; shift
  if a_gum; then
    gum style --border rounded --border-foreground "$couleur" --padding "1 2" --margin "1 0" "$@"
  else
    echo; echo "----------------------------------------------------------------"
    local l; for l in "$@"; do echo "  $l"; done
    echo "----------------------------------------------------------------"; echo
  fi
}

etape() { # etape numéro "titre"
  noter "ÉTAPE $1 : $2"
  if a_gum; then
    echo
    gum style --bold --foreground "$COULEUR_ACCENT" "Étape $1 sur $ETAPES : $2"
  else
    echo; echo "=== Étape $1 sur $ETAPES : $2 ==="
  fi
}

dire()      { if a_gum; then gum style --width 72 "$*"; else echo "$*"; fi; }
ok()        { noter "ok : $*"; if a_gum; then gum style --foreground "$COULEUR_OK" "✓ $*"; else echo "[OK] $*"; fi; }
attention() { noter "attention : $*"; if a_gum; then gum style --foreground "$COULEUR_ATTENTION" "! $*"; else echo "[!] $*"; fi; }

echec() { # echec "ce qui s'est passé" "ce qu'il faut faire"
  noter "ÉCHEC : $1"
  echo
  if a_gum; then
    gum style --border rounded --border-foreground "$COULEUR_ERREUR" --padding "1 2" --width 70 \
      "Quelque chose n'a pas marché." "" "$1" "" "Que faire : $2" "" \
      "Si ça bloque encore, prévenez $CONTACT, en lui envoyant ce fichier :" "$JOURNAL"
  else
    echo "Quelque chose n'a pas marché : $1"; echo "Que faire : $2"
    echo "Si ça bloque encore, prévenez $CONTACT, en lui envoyant ce fichier : $JOURNAL"
  fi
  exit 1
}

question() { # question "texte" -> 0 si oui
  if [ -n "$AUTO" ]; then noter "question auto (oui) : $1"; return 0; fi
  if a_gum; then
    gum confirm --affirmative "Oui" --negative "Non" "$1"
  else
    local r; printf "%s [o/n] " "$1"; read -r r; case "$r" in o|O|oui|Oui|OUI|"") return 0;; *) return 1;; esac
  fi
}

pause() {
  [ -n "$AUTO" ] && return 0
  if a_gum; then gum style --faint "Appuyez sur Entrée pour continuer…"; else echo "Appuyez sur Entrée pour continuer…"; fi
  read -r _
}

patienter() { # patienter "message" commande args... (la sortie va dans le journal)
  local titre="$1"; shift
  noter "commande : $*"
  if a_gum; then
    gum spin --spinner dot --spinner.foreground "$COULEUR_ACCENT" --title " $titre" -- bash -c '"$@" >> "'"$JOURNAL"'" 2>&1' _ "$@"
  else
    echo "… $titre"; "$@" >> "$JOURNAL" 2>&1
  fi
}

telecharger_verifie() { # telecharger_verifie url fichier sha256
  curl -fsSL --retry 3 -o "$2" "$1" >> "$JOURNAL" 2>&1 || return 1
  local calcule; calcule="$(shasum -a 256 "$2" | awk '{print $1}')"
  if [ "$calcule" != "$3" ]; then noter "empreinte inattendue pour $1 : $calcule"; return 2; fi
}

# -----------------------------------------------------------------------------
#  Vérifications de départ
# -----------------------------------------------------------------------------

if [ "$(uname -s)" != "Darwin" ]; then
  echo "Ce script est prévu pour un Mac. Sur Windows, utilisez la version PowerShell (installer.ps1)."; exit 1
fi
if [ "$(id -u)" = "0" ]; then
  echo "Lancez ce script sans « sudo », en tant que vous-même."; exit 1
fi
if [ -z "$AUTO" ] && [ ! -t 0 ]; then
  echo "Ce script a besoin de vous poser des questions."
  echo "Copiez exactement la ligne fournie par Cyremia : elle commence par  bash -c \"\$(curl"
  exit 1
fi
case "$(uname -m)" in
  arm64)  ARCH_GUM="arm64";  SHA_GUM="$GUM_SHA_ARM64";  ARCH_GH="arm64"; SHA_GH="$GH_SHA_ARM64" ;;
  x86_64) ARCH_GUM="x86_64"; SHA_GUM="$GUM_SHA_X86_64"; ARCH_GH="amd64"; SHA_GH="$GH_SHA_AMD64" ;;
  *) echo "Type de processeur non reconnu ($(uname -m)). Prévenez $CONTACT."; exit 1 ;;
esac
mkdir -p "$DOSSIER_OUTILS"

# -----------------------------------------------------------------------------
#  Étape 1 : l'outil d'affichage
# -----------------------------------------------------------------------------

echo
echo "Bonjour ! Nous préparons votre ordinateur. Un instant, on installe d'abord l'affichage…"
etape 1 "l'affichage"
if a_gum && gum --version 2>/dev/null | grep -q "v$GUM_VERSION"; then
  ok "L'affichage est déjà en place."
else
  if telecharger_verifie "https://github.com/charmbracelet/gum/releases/download/v${GUM_VERSION}/gum_${GUM_VERSION}_Darwin_${ARCH_GUM}.tar.gz" "$TEMP/gum.tgz" "$SHA_GUM" \
     && tar -xzf "$TEMP/gum.tgz" -C "$TEMP" \
     && cp "$TEMP/gum_${GUM_VERSION}_Darwin_${ARCH_GUM}/gum" "$DOSSIER_OUTILS/gum" \
     && chmod +x "$DOSSIER_OUTILS/gum"; then
    ok "L'affichage est installé."
  else
    echo "(L'affichage amélioré n'a pas pu être installé : on continue en mode simple, tout fonctionne quand même.)"
    noter "gum indisponible, mode texte"
  fi
fi

cadre "$COULEUR_ACCENT" \
  "Bienvenue ! Ce programme prépare votre ordinateur" \
  "pour que vous puissiez faire évoluer votre site vous-même," \
  "en parlant à Claude Code." \
  "" \
  "Ce qui va se passer, en 10 à 20 minutes :" \
  "  • installation d'outils gratuits (Git, GitHub, application Claude) ;" \
  "  • connexion à votre compte GitHub, dans votre navigateur ;" \
  "  • récupération de votre site dans le dossier « code » ;" \
  "  • ouverture de l'application Claude, prête à travailler." \
  "" \
  "Rien n'est supprimé sur votre ordinateur." \
  "Aucun mot de passe ne vous sera demandé ici," \
  "sauf peut-être celui de votre Mac, par Apple." \
  "En cas d'interruption, relancez simplement la même ligne."
question "On commence ?" || { dire "D'accord, rien n'a été modifié. Relancez la ligne quand vous voulez."; exit 0; }

# -----------------------------------------------------------------------------
#  Étape 2 : Git (outils de développement d'Apple)
# -----------------------------------------------------------------------------

etape 2 "les outils d'Apple (Git)"
if xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
  ok "Les outils d'Apple sont déjà installés ($(git --version | awk '{print $3}'))."
else
  cadre "$COULEUR_ATTENTION" \
    "Apple va ouvrir une petite fenêtre « Outils de ligne de commande »." \
    "" \
    "  1. Cliquez sur « Installer »." \
    "  2. Cliquez sur « Accepter » (conditions d'Apple)." \
    "  3. Patientez : le téléchargement prend 5 à 15 minutes." \
    "" \
    "Ne fermez pas cette fenêtre-ci : le programme reprend tout seul" \
    "dès que l'installation d'Apple est terminée."
  pause
  xcode-select --install >> "$JOURNAL" 2>&1
  patienter "Installation des outils d'Apple en cours (5 à 15 minutes)…" \
    bash -c 'n=0; until xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; do sleep 5; n=$((n+1)); [ $n -gt 720 ] && exit 1; done'
  if xcode-select -p >/dev/null 2>&1 && git --version >/dev/null 2>&1; then
    ok "Les outils d'Apple sont installés."
  else
    echec "Les outils d'Apple ne sont pas installés (fenêtre fermée ou installation trop longue)." \
          "relancez la même ligne et cliquez bien sur « Installer » dans la fenêtre d'Apple."
  fi
fi

# -----------------------------------------------------------------------------
#  Étape 3 : GitHub CLI
# -----------------------------------------------------------------------------

etape 3 "l'outil GitHub"
if command -v gh >/dev/null 2>&1; then
  ok "L'outil GitHub est déjà installé ($(gh --version | head -1 | awk '{print $3}'))."
else
  dossier_gh="gh_${GH_VERSION}_macOS_${ARCH_GH}"
  patienter "Téléchargement de l'outil GitHub…" \
    curl -fsSL --retry 3 -o "$TEMP/gh.zip" "https://github.com/cli/cli/releases/download/v${GH_VERSION}/${dossier_gh}.zip"
  if [ "$(shasum -a 256 "$TEMP/gh.zip" 2>/dev/null | awk '{print $1}')" != "$SHA_GH" ]; then
    echec "Le téléchargement de l'outil GitHub est incomplet ou n'est pas celui attendu." \
          "vérifiez votre connexion Internet, puis relancez la même ligne."
  fi
  unzip -q -o "$TEMP/gh.zip" -d "$TEMP" && cp "$TEMP/$dossier_gh/bin/gh" "$DOSSIER_OUTILS/gh" && chmod +x "$DOSSIER_OUTILS/gh" \
    || echec "L'outil GitHub n'a pas pu être installé." "relancez la même ligne."
  ok "L'outil GitHub est installé."
fi

# -----------------------------------------------------------------------------
#  Étape 4 : l'application Claude
# -----------------------------------------------------------------------------

app_claude() { [ -d "/Applications/Claude.app" ] || [ -d "$HOME/Applications/Claude.app" ]; }

etape 4 "l'application Claude"
if app_claude; then
  ok "L'application Claude est déjà installée."
elif [ -n "$AUTO" ]; then
  attention "Application Claude absente (mode test : on continue)."
else
  cadre "$COULEUR_ATTENTION" \
    "Installons l'application Claude, celle où vous parlerez à Claude Code." \
    "" \
    "  1. Appuyez sur Entrée : la page de téléchargement s'ouvre." \
    "  2. Cliquez sur « Download for macOS » (ou « Télécharger »)." \
    "  3. Ouvrez le fichier téléchargé (en bas de votre navigateur" \
    "     ou dans le dossier Téléchargements)." \
    "  4. Glissez l'icône Claude sur le dossier Applications." \
    "" \
    "Revenez ici ensuite : le programme reprend tout seul."
  pause
  open "https://claude.com/download"
  patienter "En attente de l'installation de l'application Claude…" \
    bash -c 'n=0; until [ -d /Applications/Claude.app ] || [ -d "$HOME/Applications/Claude.app" ]; do sleep 3; n=$((n+1)); [ $n -gt 600 ] && exit 1; done'
  if app_claude; then
    ok "L'application Claude est installée."
  else
    echec "L'application Claude n'a pas été trouvée dans le dossier Applications." \
          "vérifiez que vous avez bien glissé Claude dans Applications, puis relancez la même ligne."
  fi
fi

# Rendre les outils disponibles dans les prochaines fenêtres du Terminal
[ -n "$AUTO" ] || for profil in "$HOME/.zprofile" "$HOME/.bash_profile"; do
  if [ "$profil" = "$HOME/.bash_profile" ] && [ ! -f "$profil" ]; then continue; fi
  if ! grep -q 'Ajouté par Cyremia' "$profil" 2>/dev/null; then
    printf '\n# Ajouté par Cyremia : outils pour faire évoluer votre site\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$profil"
    noter "PATH ajouté dans $profil"
  fi
done

# -----------------------------------------------------------------------------
#  Étape 5 : connexion à GitHub
# -----------------------------------------------------------------------------

etape 5 "la connexion à votre compte GitHub"
if gh auth status --hostname github.com >/dev/null 2>&1; then
  identifiant="$(gh api user --jq .login 2>/dev/null)"
  ok "Vous êtes déjà connecté à GitHub sous le nom « $identifiant »."
  if ! question "Est-ce bien votre compte GitHub ?"; then
    gh auth logout --hostname github.com >> "$JOURNAL" 2>&1 <<< "Y"
    attention "Compte déconnecté. On vous reconnecte avec le bon compte."
  fi
fi
if ! gh auth status --hostname github.com >/dev/null 2>&1; then
  cadre "$COULEUR_ATTENTION" \
    "Nous allons relier cet ordinateur à votre compte GitHub." \
    "" \
    "  1. Un code de 8 caractères va s'afficher (exemple : ABCD-1234)." \
    "     Il est déjà copié pour vous." \
    "  2. Appuyez sur Entrée : votre navigateur s'ouvre sur GitHub." \
    "  3. Connectez-vous si besoin, collez le code (Cmd + V)," \
    "     puis cliquez sur « Continue », puis sur « Authorize github »." \
    "  4. Revenez ici : la suite démarre toute seule."
  pause
  gh auth login --hostname github.com --git-protocol https --web --clipboard --skip-ssh-key \
    || echec "La connexion à GitHub n'a pas abouti." "relancez la même ligne et suivez les quatre étapes du cadre orange."
fi
gh auth setup-git --hostname github.com >> "$JOURNAL" 2>&1
identifiant="$(gh api user --jq .login 2>/dev/null)"
[ -n "$identifiant" ] || echec "Impossible de lire votre compte GitHub." "relancez la même ligne."
ok "Connecté à GitHub sous le nom « $identifiant »."

# Identité utilisée pour signer vos modifications (adresse e-mail masquée par GitHub)
if [ -z "$(git config --global user.name 2>/dev/null)" ]; then
  nom_affiche="$(gh api user --jq '.name // .login' 2>/dev/null)"
  git config --global user.name "${nom_affiche:-$identifiant}"
fi
if [ -z "$(git config --global user.email 2>/dev/null)" ]; then
  git config --global user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
fi

# -----------------------------------------------------------------------------
#  Étape 6 : votre projet
# -----------------------------------------------------------------------------

etape 6 "votre projet"
invitations="$(gh api user/repository_invitations --jq ".[] | select(.repository.owner.login == \"$ORGANISATION\") | \"\(.id) \(.repository.name)\"" 2>>"$JOURNAL")"
if [ -n "$invitations" ]; then
  echo "$invitations" | while read -r id_invitation nom_depot; do
    if gh api -X PATCH "user/repository_invitations/$id_invitation" >> "$JOURNAL" 2>&1; then
      ok "Invitation de Cyremia acceptée pour « $nom_depot »."
    else
      attention "L'invitation pour « $nom_depot » n'a pas pu être acceptée automatiquement."
    fi
  done
fi

projets="$(gh api --paginate 'user/repos?affiliation=collaborator,organization_member&per_page=100' \
  --jq ".[] | select(.owner.login == \"$ORGANISATION\") | .name" 2>>"$JOURNAL" | sort -u)"
nombre="$(printf '%s' "$projets" | grep -c . )"
if [ "$nombre" -eq 0 ]; then
  echec "Aucun projet Cyremia n'est encore relié à votre compte GitHub « $identifiant »." \
        "donnez à Cyremia votre identifiant GitHub ( $identifiant ), attendez son invitation, puis relancez la même ligne."
elif [ -n "${CYREMIA_PROJET:-}" ] && printf '%s\n' "$projets" | grep -qx "$CYREMIA_PROJET"; then
  projet="$CYREMIA_PROJET"
elif [ "$nombre" -eq 1 ] || [ -n "$AUTO" ]; then
  projet="$(printf '%s\n' "$projets" | head -1)"
else
  dire "Plusieurs projets sont reliés à votre compte. Lequel voulez-vous ouvrir ?"
  if a_gum; then
    projet="$(printf '%s\n' "$projets" | gum choose --header "Utilisez les flèches, puis Entrée")"
  else
    printf '%s\n' "$projets" | nl; printf "Numéro : "; read -r choix; projet="$(printf '%s\n' "$projets" | sed -n "${choix}p")"
  fi
  [ -n "$projet" ] || echec "Aucun projet choisi." "relancez la même ligne et choisissez un projet."
fi
ok "Votre projet : $projet"

dossier_projet="$DOSSIER_CODE/$projet"
mkdir -p "$DOSSIER_CODE"
if [ -d "$dossier_projet/.git" ]; then
  if [ -n "$(git -C "$dossier_projet" status --porcelain 2>/dev/null)" ]; then
    attention "Votre dossier contient des modifications pas encore envoyées : on n'y touche pas."
    dire "Ouvrez Claude Code et dites-lui : « Enregistre et envoie mes modifications sur l'aperçu »."
  elif patienter "Mise à jour de votre projet…" git -C "$dossier_projet" pull --ff-only; then
    ok "Votre projet est à jour dans : $dossier_projet"
  else
    attention "La mise à jour automatique n'a pas pu se faire. Claude Code saura la terminer avec vous."
  fi
elif [ -e "$dossier_projet" ]; then
  echec "Un dossier « $projet » existe déjà dans « code » mais n'est pas un projet relié à GitHub." \
        "renommez ou déplacez ce dossier (par exemple « $projet ancien »), puis relancez la même ligne."
else
  patienter "Récupération de votre projet…" gh repo clone "$ORGANISATION/$projet" "$dossier_projet" \
    || echec "Votre projet n'a pas pu être récupéré." "vérifiez votre connexion Internet, puis relancez la même ligne."
  ok "Votre projet est dans : $dossier_projet"
fi

# Nom lisible et adresse de l'aperçu, fournis par Cyremia dans le projet (cyremia.json)
nom_projet="$projet"; apercu=""
if [ -f "$dossier_projet/cyremia.json" ]; then
  nom_projet="$(plutil -extract nom raw -o - "$dossier_projet/cyremia.json" 2>/dev/null || echo "$projet")"
  apercu="$(plutil -extract apercu raw -o - "$dossier_projet/cyremia.json" 2>/dev/null || true)"
fi

# -----------------------------------------------------------------------------
#  Étape 7 : ouvrir le projet dans l'application Claude
# -----------------------------------------------------------------------------

etape 7 "ouvrir votre site dans l'application Claude"
lignes_fin=(
  "C'est prêt !"
  ""
  "Votre site est sur votre Mac, dans le dossier :"
  "  code > $projet"
)
[ -n "$apercu" ] && lignes_fin+=("Votre aperçu en ligne : $apercu")
lignes_fin+=(
  ""
  "Pour travailler sur votre site, dans l'application Claude :"
  "  1. Ouvrez Claude et connectez-vous à VOTRE compte Claude."
  "  2. Allez dans l'onglet « Code »."
  "  3. Choisissez le dossier de votre site :"
  "     dossier personnel > code > $projet"
  "  4. Écrivez simplement ce que vous voulez changer."
  ""
  "La prochaine fois, votre site apparaîtra dans la liste des"
  "projets récents de l'onglet Code."
)
cadre "$COULEUR_OK" "${lignes_fin[@]}"
noter "terminé : $dossier_projet"

if [ -z "$AUTO" ] && question "Ouvrir l'application Claude et le dossier de votre site maintenant ?"; then
  open -R "$dossier_projet" 2>/dev/null
  open -a Claude 2>/dev/null || attention "Ouvrez l'application Claude depuis le dossier Applications."
fi
dire "À bientôt ! Vous pouvez fermer cette fenêtre."
