# Préparer votre ordinateur avec Cyremia

Ce programme prépare votre ordinateur pour que vous puissiez faire évoluer votre site
vous-même, en parlant à Claude Code. Cyremia vous l'a donné : lancez-le une seule fois,
en suivant les instructions à l'écran. Vous pourrez le relancer sans risque si quelque
chose a été interrompu.

**Avant de commencer**, il vous faut :
- un compte GitHub, et avoir donné votre identifiant GitHub à Cyremia ;
- un compte Claude (abonnement Pro ou Max) ;
- environ 20 minutes et une connexion Internet.

## Sur un Mac

1. Ouvrez l'application **Terminal** (touches Cmd + Espace, tapez « Terminal », Entrée).
2. Copiez cette ligne, collez-la dans le Terminal (Cmd + V), puis appuyez sur Entrée :

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Cyremia-Studio/poste-client/main/installer.sh)"
```

## Sur un PC Windows

1. Ouvrez **Windows PowerShell** (menu Démarrer, tapez « PowerShell », Entrée).
2. Copiez cette ligne, collez-la (clic droit ou Ctrl + V), puis appuyez sur Entrée :

```powershell
irm https://raw.githubusercontent.com/Cyremia-Studio/poste-client/main/installer.ps1 | iex
```

## Ce que fait le programme

1. Il installe l'affichage du programme (gum).
2. Il installe Git, l'outil qui garde l'historique de votre site.
3. Il installe l'outil GitHub (gh).
4. Il installe Claude Code, avec le programme officiel d'Anthropic.
5. Il relie l'ordinateur à votre compte GitHub, dans votre navigateur.
6. Il accepte l'invitation de Cyremia et récupère votre site dans le dossier `code` de
   votre dossier personnel.
7. Il crée un raccourci sur votre Bureau et ouvre Claude Code dans votre site.

Il ne crée aucun compte à votre place, ne vous demande aucun mot de passe et ne supprime
rien. Un compte rendu de son déroulement est écrit dans
`~/Library/Logs/cyremia-poste-client.log` (Mac) ou
`%LOCALAPPDATA%\Cyremia\poste-client.log` (Windows) : envoyez-le à Cyremia en cas de souci.

---

## Pour Cyremia

- **Contrat avec les dépôts clients** : le projet doit être dans l'organisation
  `Cyremia-Studio`, avoir `preprod` comme branche par défaut, et contenir à sa racine un
  fichier `cyremia.json` :

  ```json
  { "nom": "Mon site", "apercu": "https://exemple.cyremia.cloud" }
  ```

  `nom` sert au raccourci du Bureau, `apercu` est affiché à la fin. Les deux sont facultatifs.
- **Ce dépôt est public** pour que le client puisse le télécharger avant d'être connecté à
  GitHub. Il ne doit contenir **aucun nom de client, aucune référence d'infrastructure,
  aucun secret**.
- **Versions épinglées** : gum `2.0.2` et GitHub CLI `2.103.2`, vérifiées par empreinte
  SHA-256 (variables en tête des deux scripts). Pour monter de version : prendre une
  version publiée depuis au moins deux semaines, recopier les empreintes depuis le
  fichier `checksums.txt` de la publication, tester sur un Mac et sur un PC.
- **Tester sans toucher à son poste** :
  `CYREMIA_AUTO=oui CYREMIA_DOSSIER_CODE=/tmp/essai CYREMIA_DOSSIER_OUTILS=/tmp/outils bash installer.sh`
  (répond « oui » partout, prend le premier projet, ne crée pas de raccourci, n'ouvre pas
  Claude Code, ne modifie pas le profil du Terminal).
- Toute modification passe par une branche et une relecture : ce script s'exécute sur les
  postes de tous les clients.
