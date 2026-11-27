- 🟡 **MyWeli Pro, « Équipe » : l’adresse de chaque membre entière, coupée seulement à ses jointures (app · 2026-11-27, la parité avec le site #902, [app-team-email-seams.md](../../design/app-team-email-seams.md)).** PR #PRNUM, branche `fix/app-team-email-seams`, créée depuis `main` (`cee647eb`). Règle : [SYSTEM.md](../../design/SYSTEM.md) §13.3, §21 ligne 99.
  - **Mesuré avant de construire** (vraie police, 360 et 390 dp, 1× et 2×). La liste coupait chaque adresse avec « … », même à la taille normale (« aminata.kone… », « awa@exempl… » ; l’image de référence `pro_team.png` le montrait : « fatou.reception@… »). À 200 %, une ligne n’en montrait qu’une à quatre lettres (« a… », « ko… »). La feuille d’actions la coupait, et « Révoquer l’accès ? », l’étape du rôle et les quatre messages la coupaient au milieu d’un mot (« aminata.kone@exe » / « mple.ci perdra »).
  - **Accordé par le propriétaire :** « Approve as recommended », puis « Drop it everywhere ».
  - **Ce qui change :**
    - la liste : l’adresse est le titre de la ligne, entière ; la pastille du rôle passe dessous ; l’avatar à l’initiale disparaît ;
    - la feuille d’actions : l’adresse en titre, la pastille dessous ;
    - « Révoquer l’accès ? » : l’adresse d’abord, sur sa propre ligne, à l’encre, puis la phrase ; un lecteur d’écran entend la phrase d’avant ;
    - l’étape du rôle : « Quel rôle pour », puis l’adresse ; le « ? » s’entend, il ne se dessine pas ;
    - les quatre messages disent ce qui s’est passé, sans l’adresse : « Invitation envoyée. », « Invitation renvoyée. », « Accès révoqué. », « Rôle mis à jour. », les mots du site.

    `EmailSentence` dessine une phrase qui nomme une adresse ; `CodeSentTo` passe par lui, sans changer de forme (ses images de référence sont identiques à l’octet).
  - **Trouvé en regardant la première image à 200 %** (Linux) : les adresses de démonstration coupées dans leur domaine, « @myweli.tes » / « t ». Un domaine est d’un seul tenant, et l’avatar ne laissait que 192 dp ; `@hotmail.com`, `@outlook.com` et notre `@myweli.com` mesurent 205 à 214 dp à 2×. Les tests ne le voyaient pas : leurs adresses finissaient toutes en `@exemple.ci` ou `@gmail.com`. La question est retournée au propriétaire, qui a répondu « Drop it everywhere ». Sans l’avatar, le titre a 248 dp et chaque domaine courant tient.
  - **Rouge d’abord,** sur le code d’avant : 14 tests, chacun pour sa raison ; puis 2 de plus pour l’avatar (192 dp pour « @outlook.com » ; l’initiale entendue avant l’adresse). Le garde-fou `expectEmailAddressOnItsOwnLine` gagne `within:`, pour qu’une feuille ou une boîte de dialogue soit jugée seule, et non sur la ligne dessinée derrière elle.
  - **Vert :** toute la suite de l’app sur `3bebc7e7` : 4 626 réussis, 105 ignorés (les images de référence, hors Linux) ; analyze 0 ; format propre. Deux images de référence faites sous Linux (run 46057752952) et regardées : `pro_team` et la nouvelle `pro_team_w360_x2`. Les autres, celles de l’étape du code comprises, sont identiques à l’octet.
  - **Mutations, sur le code commité :** 27, toutes rouges, l’arbre propre avant et après chacune. Deux ont d’abord été mal visées et ont été reprises : l’une ne s’appliquait pas (le formateur avait coupé sa ligne), l’autre jetait un débordement de mise en page au lieu de faire échouer le garde-fou.
  - **Reste ouvert :**
    - `expectNoLegibilityCrush` ne voit pas un texte coupé par « … » sans `maxLines` (il le mesure comme s’il pouvait aller à la ligne) ;
    - deux autres écrans Pro dessinent une adresse, non mesurés : le « Profil » Pro et le « Compte : {email} » de l’inscription Android ;
    - un seul morceau plus large qu’une ligne se coupe encore dedans.
  - **Reste, sur le mot du propriétaire :** la fusion, puis la prochaine version de MyWeli Pro, qui la porte.
