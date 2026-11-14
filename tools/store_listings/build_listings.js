// Writes docs/STORE_LISTINGS/<locale>.md for LiShi Mahjong 1.1.0 from the texts below, with
// counts computed here (Unicode code points; Apple keywords in UTF-8 bytes) and hard limits
// checked: the script fails instead of writing a field that is too long.
//   node tools/store_listings/build_listings.js
// Every claim must be true for the shipped build. Sample code LS-5VSW-11BK is
// StudioBoard.SAMPLE_CODE (a real, playable board).
const fs = require('fs');
const path = require('path');

const OUT = path.join(__dirname, '..', '..', 'docs', 'STORE_LISTINGS');
const VERSION = '1.1.0';
const LIMITS = {name: 30, short: 80, subtitle: 30, promo: 170, description: 4000, keywords: 100, whatsNew: 500};
const chars = (s) => [...s].length;
const bytes = (s) => Buffer.byteLength(s, 'utf8');

const L = {
  en: {
    title: 'English (en)', locales: 'Google Play `en-US` (copy to `en-GB` / `en-AU` / `en-CA` if desired) · Apple `English (U.S.)` (copy to `English (U.K.)` etc.)',
    name: 'LiShi Mahjong',
    short: 'Calm Mahjong tile puzzles for 1 or 2 players. Build boards, share codes.',
    subtitle: 'Play Together · Build & Share',
    promo: 'New: Play Together – two players, one phone, one board. And Board Studio – build a board, our solver proves it can be cleared, share it as a code.',
    keywords: 'co-op,pass and play,2 player,family,level maker,builder,share code,tile,solitaire,daily,zen',
    description: `LiShi Mahjong is a calm Mahjong tile puzzle you can play on your own, side by side with someone you love, or on boards you build yourself.

PLAY TOGETHER
Two players share one phone, one board and one tray. Take turns, one tile each, and clear the board as a team. Finish the pair your partner started for a Team-up bonus. It works offline and needs no accounts: made for couples, friends, parents and kids, grandparents and grandchildren.

BOARD STUDIO
Build your own board: choose one of 10 shapes, how many tiles and how many layers. Before you play, the game's solver checks that the board can be cleared. Every board gets a short code – try LS-5VSW-11BK. Send yours to a friend and they play exactly the same board. Keep up to 30 boards in My boards.

FAIR BY PROOF
All 600 levels are checked by the same solver. A hint shows the next move of a solution the solver found, and says so when there was no time to check. If the solver proves the tiles left can't be cleared, the game tells you, and going back to the last solvable point costs nothing.

HOW TO PLAY
Tap a free tile (nothing on top, and its left or right side open) and it moves into the tray. Two identical tiles clear. Four unmatched tiles fill the tray, so the order you pick in matters.

600 LEVELS IN 6 WORLDS
Aurora Garden, Pearl Coast, Crystal Nocturne, Jade Bamboo Valley, Sunset Lotus Palace and Frostlight Village, with layered boards that grow as you travel.

A DAILY PUZZLE
A new board every day, the same for everyone and playable offline. The last 30 days stay in the archive.

WATCH YOUR WORLD BLOOM
Each new level earns a LiShi Light. Every 5 Lights reveal one of 60 discoveries in LiShi Bloom.

COMFORTABLE TO PLAY
• No timers, lives or energy
• Large Tiles, High Contrast, Reduce Motion, Dim Blocked Tiles and Soften Background
• Adjustable sound; vibration can be turned off
• 4 tile themes and 3 tile backs to collect

Coins earned in play buy Hints, Undos and Shuffles. Optional in-app purchases include coin packs and Remove Ads; every level can be finished without paying.

Available in English, Hebrew, Japanese, Korean, German, French, Spanish, Brazilian Portuguese, Traditional Chinese and Russian.`,
    notes: [
      'English is the source text. Check every claim against the build before uploading.',
      'Feature names match the game: Play Together, Board Studio, Team-up, My boards, LiShi Bloom, LiShi Light.',
      '"LS-5VSW-11BK" is a real code (StudioBoard.SAMPLE_CODE); keep it in sync if the sample changes.',
    ],
  },
  he: {
    title: 'Hebrew (he)', locales: 'Google Play `iw-IL` · Apple `Hebrew`',
    name: 'LiShi Mahjong',
    short: "פאזל אריחי מהג'ונג רגוע לשחקן אחד או לשניים. בונים לוחות ומשתפים בקוד.",
    subtitle: 'משחק בשניים · בונים ומשתפים',
    promo: 'חדש: משחק בשניים – שני שחקנים, טלפון אחד ולוח אחד. וגם סטודיו לוחות – בונים לוח, הפותר מוכיח שאפשר לפנות אותו, ומשתפים אותו בקוד.',
    keywords: 'בשניים,משפחה,זוגי,אריחים,פאזל,יומי,לוחות,קוד,רגוע',
    description: `LiShi Mahjong הוא פאזל אריחי מהג'ונג רגוע שאפשר לשחק לבד, יחד עם מישהו קרוב, או על לוחות שבונים בעצמכם.

משחק בשניים
שני שחקנים חולקים טלפון אחד, לוח אחד ומגש אחד. משחקים בתורות, אריח אחד כל אחד, ומפנים את הלוח כצוות. השלימו את הזוג שהשותף התחיל וקבלו בונוס עבודת צוות. עובד בלי אינטרנט ובלי חשבון: לזוגות, לחברים, להורים וילדים, לסבים ולנכדים.

סטודיו לוחות
בונים לוח משלכם: בוחרים אחת מ-10 צורות, כמה אריחים וכמה שכבות. לפני שמשחקים, הפותר של המשחק בודק שאפשר לפנות את הלוח. לכל לוח יש קוד קצר – נסו את LS-5VSW-11BK. שלחו את הקוד שלכם לחבר והוא ישחק בדיוק באותו הלוח. אפשר לשמור עד 30 לוחות בלוחות שלי.

הוגן, וזה מוכח
כל 600 השלבים נבדקו באותו פותר. רמז מראה את המהלך הבא בפתרון שהפותר מצא, ואומר כשלא היה זמן לבדוק. אם הפותר מוכיח שאי אפשר לפנות את האריחים שנשארו, המשחק אומר לכם, והחזרה לנקודה הפתירה האחרונה לא עולה כלום.

איך משחקים
מקישים על אריח פנוי (אין עליו כלום, והצד הימני או השמאלי שלו פנוי) והוא עובר למגש. שני אריחים זהים נעלמים. ארבעה אריחים בלי זוג ממלאים את המגש, ולכן הסדר חשוב.

600 שלבים ב-6 עולמות
גן הזוהר, חוף הפנינה, ליל הקריסטלים, עמק הבמבוק הירוק, ארמון הלוטוס בשקיעה וכפר אורות השלג, עם לוחות בשכבות שגדלים לאורך הדרך.

פאזל יומי
לוח חדש בכל יום, זהה לכולם, ואפשר לשחק בו בלי אינטרנט. 30 הימים האחרונים נשמרים בארכיון.

העולם שלכם פורח
כל שלב חדש מעניק אור LiShi. כל 5 אורות חושפים אחת מ-60 תגליות ב-LiShi Bloom.

נוח לשחק
• בלי טיימרים, חיים או אנרגיה
• אריחים גדולים, ניגודיות גבוהה, הפחתת תנועה, הכהיית אריחים חסומים ורקע רך
• שליטה בצליל, ואפשר לכבות רטט
• 4 ערכות אריחים ו-3 גבי אריחים לאסוף

מטבעות שצוברים במשחק קונים רמזים, ביטולי מהלך וערבובים. רכישות אופציונליות כוללות חבילות מטבעות והסרת פרסומות; את כל השלבים אפשר לסיים בלי לשלם.

זמין בעברית, אנגלית, יפנית, קוריאנית, גרמנית, צרפתית, ספרדית, פורטוגזית (ברזיל), סינית מסורתית ורוסית.`,
    notes: [
      'Plural address (אתם) as in the game. World names must match he.json (check "חוף הפנינים", "לילה בדולחי", etc.).',
      'Accessibility option names should match the Settings screen wording exactly.',
    ],
  },
  ja: {
    title: 'Japanese (ja)', locales: 'Google Play `ja-JP` · Apple `Japanese`',
    name: 'LiShi Mahjong',
    short: '1人でも2人でも遊べる、やさしい麻雀牌パズル。盤面を作ってコードで共有。',
    subtitle: 'ふたりで遊ぶ・作って共有',
    promo: '新登場：ふたりで遊ぶ ― 1台のスマホ、1つの盤面をふたりで。ボードスタジオ ― 盤面を作ると、ソルバーがクリアできることを証明。コードで共有できます。',
    keywords: '麻雀,ソリティア,協力,ふたり,家族,パズル,牌,デイリー',
    description: `LiShi Mahjong は、ひとりでも、大切な人と並んでも、自分で作った盤面でも遊べる、やさしい麻雀牌パズルです。

ふたりで遊ぶ
1台のスマホで、1つの盤面と1つのトレイをふたりで使います。1人1枚ずつ交代で選び、チームで盤面を消していきます。相手が置いた牌のペアをそろえるとチームワークボーナス。オフラインで、アカウントも不要。夫婦や友だち、親子、祖父母と孫に。

ボードスタジオ
10種類の形から1つを選び、牌の数と段数を決めて自分の盤面を作れます。遊ぶ前に、ゲームのソルバーがクリアできることを確認します。盤面ごとに短いコードがつきます（例：LS-5VSW-11BK）。友だちに送れば、まったく同じ盤面で遊べます。マイ盤面には30個まで保存できます。

公平さを証明
600レベルすべてを同じソルバーで確認済み。ヒントはソルバーが見つけた解き方の次の一手を示し、確認が間に合わなかったときはそう伝えます。残りの牌がクリアできないことをソルバーが証明したときは知らせてくれて、最後に解けた地点へ無料で戻れます。

遊び方
空いている牌（上に何もなく、左か右が空いている牌）をタップするとトレイへ。同じ牌が2枚そろうと消えます。そろわない牌が4枚でトレイがいっぱいになるので、選ぶ順番が大切です。

6つの世界に600レベル
オーロラガーデン、パールコースト、クリスタルノクターン、翡翠の竹の谷、夕焼けの蓮の宮殿、霜灯りの村。旅が進むほど盤面が大きく、段も高くなります。

デイリーパズル
毎日新しい盤面がひとつ。みんな同じ盤面で、オフラインでも遊べます。過去30日分はアーカイブに残ります。

庭が花開く
新しいレベルをクリアするたびにLiShiの光をひとつ。光5つで、LiShi Bloomの60の発見のひとつが現れます。

遊びやすさ
• タイマー、ライフ、スタミナなし
• 大きな牌、ハイコントラスト、動きを減らす、ふさがれた牌を暗く、背景をやわらかく
• 音量の調整、振動のオフ
• 集められる牌のテーマ4種と牌の裏面3種

プレイで貯めたコインでヒント、戻す、シャッフルが使えます。コインパックや広告の削除などのアプリ内課金は任意で、すべてのレベルは課金なしでクリアできます。

日本語、英語、ヘブライ語、韓国語、ドイツ語、フランス語、スペイン語、ブラジルポルトガル語、繁体字中国語、ロシア語に対応。`,
    notes: ['World names and option names must match ja.json; check "翡翠の竹の谷", "夕焼けの蓮の宮殿", "霜灯りの村".'],
  },
  ko: {
    title: 'Korean (ko)', locales: 'Google Play `ko-KR` · Apple `Korean`',
    name: 'LiShi Mahjong',
    short: '혼자서도 둘이서도 즐기는 차분한 마작 패 퍼즐. 보드를 만들고 코드로 공유해요.',
    subtitle: '함께 플레이 · 만들고 공유',
    promo: '새 기능: 함께 플레이 – 휴대폰 하나, 보드 하나로 두 사람이 함께. 보드 스튜디오 – 보드를 만들면 솔버가 클리어 가능함을 증명하고, 코드로 공유할 수 있어요.',
    keywords: '마작,솔리테어,협동,2인,가족,퍼즐,타일,데일리',
    description: `LiShi Mahjong은 혼자서도, 소중한 사람과 나란히도, 직접 만든 보드로도 즐길 수 있는 차분한 마작 패 퍼즐이에요.

함께 플레이
두 사람이 휴대폰 하나, 보드 하나, 트레이 하나를 함께 써요. 한 사람씩 번갈아 패를 하나씩 고르며 팀으로 보드를 치워요. 상대가 넣은 패의 짝을 맞추면 팀워크 보너스! 오프라인으로, 계정 없이 즐길 수 있어요. 커플, 친구, 부모와 아이, 조부모와 손주에게 딱 맞아요.

보드 스튜디오
10가지 모양 중 하나를 고르고 패 개수와 층수를 정해 나만의 보드를 만들어요. 플레이 전에 게임의 솔버가 보드를 클리어할 수 있는지 확인해요. 모든 보드에는 짧은 코드가 붙어요(예: LS-5VSW-11BK). 친구에게 보내면 똑같은 보드로 플레이할 수 있어요. 내 보드에는 30개까지 저장할 수 있어요.

증명된 공정함
600개 레벨 모두 같은 솔버로 확인했어요. 힌트는 솔버가 찾은 풀이의 다음 수를 보여 주고, 확인할 시간이 부족했을 때는 그렇다고 알려 줘요. 남은 패를 치울 수 없다는 것이 증명되면 알려 주고, 마지막으로 풀 수 있던 곳으로 무료로 돌아갈 수 있어요.

플레이 방법
빈 패(위에 아무것도 없고 왼쪽이나 오른쪽이 비어 있는 패)를 탭하면 트레이로 이동해요. 같은 패 두 개가 모이면 사라져요. 짝이 없는 패 4개로 트레이가 가득 차니 고르는 순서가 중요해요.

6개 세계, 600개 레벨
오로라 정원, 진주 해안, 크리스털 녹턴, 비취 대나무 계곡, 노을 연꽃 궁전, 서리빛 마을. 여행할수록 보드가 커지고 층이 높아져요.

데일리 퍼즐
매일 새로운 보드 하나. 모두에게 같은 보드이고 오프라인에서도 플레이할 수 있어요. 최근 30일은 기록실에 남아요.

피어나는 정원
새 레벨을 클리어할 때마다 LiShi의 빛을 얻어요. 빛 5개마다 LiShi Bloom의 60가지 발견 중 하나가 나타나요.

편안한 플레이
• 타이머, 생명, 에너지 없음
• 큰 패, 고대비, 움직임 줄이기, 막힌 패 어둡게, 배경 부드럽게
• 소리 조절, 진동 끄기
• 모을 수 있는 패 테마 4종과 패 뒷면 3종

플레이로 모은 코인으로 힌트, 되돌리기, 섞기를 사용해요. 코인 팩과 광고 제거 같은 인앱 구매는 선택 사항이며, 모든 레벨은 결제 없이 클리어할 수 있어요.

한국어, 영어, 히브리어, 일본어, 독일어, 프랑스어, 스페인어, 브라질 포르투갈어, 번체 중국어, 러시아어를 지원해요.`,
    notes: ['World and option names must match ko.json.'],
  },
  de: {
    title: 'German (de)', locales: 'Google Play `de-DE` · Apple `German`',
    name: 'LiShi Mahjong',
    short: 'Entspannte Mahjong-Steinrätsel für 1 oder 2 Spieler. Bretter bauen & teilen.',
    subtitle: 'Zu zweit · Bauen & Teilen',
    promo: 'Neu: Zu zweit spielen – zwei Spieler, ein Handy, ein Feld. Und das Brett-Studio – bau ein Brett, unser Löser beweist, dass es lösbar ist, und teil es per Code.',
    keywords: 'koop,zu zweit,familie,editor,code,steine,solitär,täglich,rätsel,entspannt',
    description: `LiShi Mahjong ist ein entspanntes Mahjong-Steinrätsel – allein, zu zweit mit einem lieben Menschen oder auf Brettern, die du selbst baust.

ZU ZWEIT SPIELEN
Zwei Spieler teilen sich ein Handy, ein Feld und eine Ablage. Ihr wechselt euch ab, je ein Stein pro Zug, und räumt das Feld als Team ab. Wer das Paar des anderen vervollständigt, bekommt einen Teamwork-Bonus. Funktioniert offline und ohne Konto: für Paare, Freunde, Eltern und Kinder, Großeltern und Enkel.

BRETT-STUDIO
Bau dein eigenes Brett: Wähle eine von 10 Formen, die Zahl der Steine und der Ebenen. Bevor du spielst, prüft der Löser des Spiels, dass das Brett lösbar ist. Jedes Brett bekommt einen kurzen Code – probier LS-5VSW-11BK. Schick deinen einem Freund, und er spielt genau dasselbe Brett. In „Meine Bretter“ passen bis zu 30 Bretter.

FAIR, UND BEWIESEN
Alle 600 Level sind mit demselben Löser geprüft. Ein Tipp zeigt den nächsten Zug einer Lösung, die der Löser gefunden hat, und sagt es, wenn die Zeit zum Prüfen nicht reichte. Beweist der Löser, dass die restlichen Steine nicht mehr abgeräumt werden können, sagt dir das Spiel Bescheid, und zurück zum letzten lösbaren Punkt geht es gratis.

SO GEHT’S
Tippe einen freien Stein an (nichts liegt darauf, und seine linke oder rechte Seite ist frei), und er wandert in die Ablage. Zwei gleiche Steine verschwinden. Vier Steine ohne Paar füllen die Ablage – die Reihenfolge zählt.

600 LEVEL IN 6 WELTEN
Aurora-Garten, Perlenküste, Kristall-Nocturne, Jadebambus-Tal, Lotuspalast im Abendrot und Frostlicht-Dorf, mit Feldern in Ebenen, die unterwegs wachsen.

EIN TÄGLICHES RÄTSEL
Jeden Tag ein neues Feld, für alle gleich und offline spielbar. Die letzten 30 Tage bleiben im Archiv.

LASS DEINE WELT ERBLÜHEN
Jedes neue Level bringt ein LiShi-Licht. Je 5 Lichter enthüllen eine von 60 Entdeckungen in LiShi Bloom.

ANGENEHM ZU SPIELEN
• Keine Timer, Leben oder Energie
• Große Steine, Hoher Kontrast, Weniger Bewegung, Blockierte Steine abdunkeln und Weicher Hintergrund
• Einstellbarer Ton; Vibration abschaltbar
• 4 Stein-Designs und 3 Steinrückseiten zum Sammeln

Im Spiel verdiente Münzen kaufen Tipps, Zurück und Mischen. Optionale In-App-Käufe sind Münzpakete und Werbung entfernen; jedes Level ist ohne Bezahlen schaffbar.

Auf Deutsch, Englisch, Hebräisch, Japanisch, Koreanisch, Französisch, Spanisch, brasilianischem Portugiesisch, traditionellem Chinesisch und Russisch.`,
    notes: ['World names and option names must match de.json (e.g. "Kristall-Nocturne" may need a different world name — check de.json).'],
  },
  fr: {
    title: 'French (fr)', locales: 'Google Play `fr-FR` · Apple `French`',
    name: 'LiShi Mahjong',
    short: 'Puzzles de tuiles Mahjong apaisants, à 1 ou 2 joueurs. Créez et partagez.',
    subtitle: 'Jouer à deux · Créer, partager',
    promo: 'Nouveau : Jouer à deux – deux joueurs, un téléphone, une grille. Studio de grilles – créez une grille, le solveur prouve qu’elle est faisable, partagez son code.',
    keywords: 'coop,à deux,famille,éditeur,code,tuiles,solitaire,quotidien,zen,casse-tête',
    description: `LiShi Mahjong est un puzzle de tuiles Mahjong apaisant, à jouer seul, à deux avec un proche, ou sur des grilles que vous créez vous-même.

JOUER À DEUX
Deux joueurs partagent un téléphone, une grille et un plateau. Jouez chacun votre tour, une tuile chacun, et videz la grille en équipe. Complétez la paire commencée par votre partenaire pour un bonus d’équipe. Sans connexion ni compte : pour les couples, les amis, les parents et les enfants, les grands-parents et les petits-enfants.

STUDIO DE GRILLES
Créez votre grille : choisissez une forme parmi 10, le nombre de tuiles et d’étages. Avant de jouer, le solveur du jeu vérifie que la grille est faisable. Chaque grille a un code court – essayez LS-5VSW-11BK. Envoyez le vôtre à un ami : il jouera exactement la même grille. Gardez jusqu’à 30 grilles dans Mes grilles.

ÉQUITABLE, C’EST PROUVÉ
Les 600 niveaux sont vérifiés par le même solveur. Un indice montre le coup suivant d’une solution trouvée par le solveur, et le signale quand il n’a pas eu le temps de vérifier. Si le solveur prouve que les tuiles restantes ne peuvent plus être retirées, le jeu vous le dit, et revenir au dernier point faisable est gratuit.

COMMENT JOUER
Touchez une tuile libre (rien dessus, et son côté gauche ou droit libre) : elle va dans le plateau. Deux tuiles identiques disparaissent. Quatre tuiles sans paire remplissent le plateau : l’ordre compte.

600 NIVEAUX, 6 MONDES
Jardin Aurore, Côte des Perles, Nocturne de cristal, Vallée du bambou de jade, Palais du lotus au couchant et Village de la lueur du givre, avec des grilles en étages qui grandissent au fil du voyage.

UN PUZZLE PAR JOUR
Une nouvelle grille chaque jour, la même pour tous, jouable hors ligne. Les 30 derniers jours restent dans les archives.

FAITES FLEURIR VOTRE MONDE
Chaque nouveau niveau rapporte une Lumière LiShi. Toutes les 5 Lumières, l’une des 60 découvertes de LiShi Bloom apparaît.

CONFORTABLE
• Pas de chrono, de vies ni d’énergie
• Grandes tuiles, Contraste élevé, Moins d’animations, Assombrir les tuiles bloquées et Adoucir le fond
• Son réglable ; vibrations désactivables
• 4 thèmes de tuiles et 3 dos de tuiles à collectionner

Les pièces gagnées en jouant achètent des Indices, des Annulations et des Mélanges. Les achats intégrés (packs de pièces, Supprimer les pubs) sont facultatifs ; chaque niveau peut être terminé sans payer.

Disponible en français, anglais, hébreu, japonais, coréen, allemand, espagnol, portugais du Brésil, chinois traditionnel et russe.`,
    notes: ['In-game French uses "plateau" for the tray and "grille" for the board in the new Play Together/Studio strings; world and option names must match fr.json.'],
  },
  es: {
    title: 'Spanish (es)', locales: 'Google Play `es-ES` / `es-419` (review each) · Apple `Spanish (Spain)` / `Spanish (Mexico)`',
    name: 'LiShi Mahjong',
    short: 'Puzzles de fichas Mahjong relajantes para 1 o 2 jugadores. Crea y comparte.',
    subtitle: 'Jugar juntos · Crea y comparte',
    promo: 'Nuevo: Jugar juntos – dos jugadores, un teléfono, un tablero. Estudio de tableros – crea un tablero, el solucionador demuestra que tiene solución, compártelo por código.',
    keywords: 'cooperativo,dos jugadores,familia,editor,código,fichas,solitario,diario,zen',
    description: `LiShi Mahjong es un puzzle de fichas Mahjong relajante para jugar solo, junto a alguien querido o en tableros que creas tú.

JUGAR JUNTOS
Dos jugadores comparten un teléfono, un tablero y una bandeja. Por turnos, una ficha cada uno, despejan el tablero en equipo. Completa la pareja que empezó tu compañero y gana un bonus de equipo. Funciona sin conexión y sin cuentas: para parejas, amigos, padres e hijos, abuelos y nietos.

ESTUDIO DE TABLEROS
Crea tu propio tablero: elige una de 10 formas, cuántas fichas y cuántas capas. Antes de jugar, el solucionador del juego comprueba que el tablero se puede despejar. Cada tablero tiene un código corto: prueba LS-5VSW-11BK. Envía el tuyo a un amigo y jugará exactamente el mismo tablero. Guarda hasta 30 tableros en Mis tableros.

JUSTO, Y DEMOSTRADO
Los 600 niveles están comprobados por el mismo solucionador. Una pista muestra el siguiente movimiento de una solución que encontró el solucionador, y avisa cuando no hubo tiempo para comprobarlo. Si el solucionador demuestra que las fichas restantes ya no se pueden despejar, el juego te lo dice, y volver al último punto con solución es gratis.

CÓMO SE JUEGA
Toca una ficha libre (nada encima y su lado izquierdo o derecho libre) y pasa a la bandeja. Dos fichas iguales desaparecen. Cuatro fichas sin pareja llenan la bandeja, así que el orden importa.

600 NIVELES EN 6 MUNDOS
Jardín Aurora, Costa de Perlas, Nocturno de Cristal, Valle del Bambú de Jade, Palacio del Loto al Atardecer y Aldea Luz de Escarcha, con tableros en capas que crecen durante el viaje.

UN PUZZLE DIARIO
Un tablero nuevo cada día, el mismo para todos y jugable sin conexión. Los últimos 30 días quedan en el archivo.

HAZ FLORECER TU MUNDO
Cada nivel nuevo te da una Luz de LiShi. Cada 5 Luces aparece uno de los 60 descubrimientos de LiShi Bloom.

CÓMODO DE JUGAR
• Sin temporizadores, vidas ni energía
• Fichas grandes, Alto contraste, Reducir movimiento, Oscurecer fichas bloqueadas y Suavizar fondo
• Sonido ajustable; la vibración se puede desactivar
• 4 temas de fichas y 3 reversos para coleccionar

Las monedas que ganas jugando compran Pistas, Deshacer y Mezclar. Las compras dentro de la app (paquetes de monedas, Quitar anuncios) son opcionales; todos los niveles se pueden terminar sin pagar.

Disponible en español, inglés, hebreo, japonés, coreano, alemán, francés, portugués de Brasil, chino tradicional y ruso.`,
    notes: ['World and option names must match es.json.'],
  },
  'pt-BR': {
    title: 'Brazilian Portuguese (pt-BR)', locales: 'Google Play `pt-BR` · Apple `Portuguese (Brazil)`',
    name: 'LiShi Mahjong',
    short: 'Quebra-cabeças Mahjong tranquilos para 1 ou 2 jogadores. Crie e compartilhe.',
    subtitle: 'Jogar juntos · Crie e divida',
    promo: 'Novo: Jogar juntos – dois jogadores, um celular, um tabuleiro. Estúdio de tabuleiros – crie um tabuleiro, o solucionador prova que tem solução, compartilhe o código.',
    keywords: 'cooperativo,dois jogadores,família,editor,código,peças,paciência,diário,zen',
    description: `LiShi Mahjong é um quebra-cabeça de peças Mahjong tranquilo para jogar sozinho, ao lado de alguém querido ou em tabuleiros que você mesmo cria.

JOGAR JUNTOS
Dois jogadores dividem um celular, um tabuleiro e uma bandeja. Revezem, uma peça cada um, e limpem o tabuleiro em equipe. Complete o par que seu parceiro começou para ganhar um bônus de equipe. Funciona off-line e sem conta: para casais, amigos, pais e filhos, avós e netos.

ESTÚDIO DE TABULEIROS
Crie seu tabuleiro: escolha um de 10 formatos, quantas peças e quantas camadas. Antes de jogar, o solucionador do jogo verifica se dá para limpar o tabuleiro. Cada tabuleiro tem um código curto – experimente LS-5VSW-11BK. Envie o seu para um amigo e ele joga exatamente o mesmo tabuleiro. Guarde até 30 tabuleiros em Meus tabuleiros.

JUSTO, E COMPROVADO
Os 600 níveis foram verificados pelo mesmo solucionador. Uma dica mostra o próximo lance de uma solução encontrada pelo solucionador e avisa quando não houve tempo de verificar. Se o solucionador prova que as peças restantes não podem mais ser limpas, o jogo avisa, e voltar ao último ponto com solução é grátis.

COMO JOGAR
Toque em uma peça livre (nada por cima e o lado esquerdo ou direito livre) e ela vai para a bandeja. Duas peças iguais somem. Quatro peças sem par enchem a bandeja, então a ordem importa.

600 NÍVEIS EM 6 MUNDOS
Jardim da Aurora, Costa das Pérolas, Noturno de Cristal, Vale do Bambu de Jade, Palácio do Lótus ao Pôr do Sol e Vila da Luz Gelada, com tabuleiros em camadas que crescem na jornada.

UM QUEBRA-CABEÇA POR DIA
Um tabuleiro novo todo dia, igual para todos e jogável off-line. Os últimos 30 dias ficam no arquivo.

VEJA SEU MUNDO FLORESCER
Cada nível novo dá uma Luz de LiShi. A cada 5 Luzes surge uma das 60 descobertas do LiShi Bloom.

CONFORTÁVEL DE JOGAR
• Sem cronômetros, vidas ou energia
• Peças grandes, Alto contraste, Reduzir movimento, Escurecer peças bloqueadas e Suavizar fundo
• Som ajustável; vibração pode ser desligada
• 4 temas de peças e 3 versos para colecionar

As moedas ganhas jogando compram Dicas, Desfazer e Embaralhar. Compras no app (pacotes de moedas, Remover anúncios) são opcionais; todo nível pode ser concluído sem pagar.

Disponível em português do Brasil, inglês, hebraico, japonês, coreano, alemão, francês, espanhol, chinês tradicional e russo.`,
    notes: ['World and option names must match pt-BR.json.'],
  },
  'zh-Hant-TW': {
    title: 'Traditional Chinese (zh-Hant-TW)', locales: 'Google Play `zh-TW` · Apple `Chinese (Traditional)`',
    name: 'LiShi Mahjong',
    short: '一個人或兩個人都能玩的悠閒麻將牌益智遊戲。自己製作牌陣，用代碼分享。',
    subtitle: '雙人同樂・製作並分享',
    promo: '全新：雙人同樂 ― 兩個人、一支手機、一局牌。還有牌陣工作室 ― 自己做牌陣，求解器證明可以清完，再用代碼分享。',
    keywords: '麻將,接龍,雙人,合作,家庭,益智,牌陣,每日',
    description: `LiShi Mahjong 是悠閒的麻將牌益智遊戲：可以自己玩、和重要的人一起玩，也能玩自己製作的牌陣。

雙人同樂
兩個人共用一支手機、一局牌和一個托盤。輪流進行，每人每次選一張牌，一起把牌清光。幫隊友湊成對子，就能拿到合作獎勵。不需網路、不用帳號：適合情侶、朋友、親子，也適合祖孫一起玩。

牌陣工作室
自己打造牌陣：從 10 種形狀中選一種，再決定牌數和層數。開始前，遊戲的求解器會確認牌陣可以清完。每個牌陣都有一組短代碼，試試 LS-5VSW-11BK。把你的代碼傳給朋友，對方就能玩一模一樣的牌陣。「我的牌陣」最多可存 30 個。

公平，有證明
全部 600 個關卡都經過同一個求解器確認。提示會顯示求解器找到的解法的下一步；來不及確認時也會說明。若求解器證明剩下的牌已無法清完，遊戲會告訴你，而且回到最後可解處不用任何費用。

玩法
點選可選的牌（上面沒有牌，左側或右側空著），牌就會進入托盤。兩張相同的牌會消除。四張沒有成對的牌會塞滿托盤，所以選牌順序很重要。

6 個世界、600 個關卡
極光花園、珍珠海岸、水晶夜曲、翠竹幽谷、夕照蓮花宮與霜光小村，層疊的牌局會隨著旅程越來越大。

每日謎題
每天一局新牌，所有人都一樣，離線也能玩。最近 30 天會保留在檔案中。

讓你的世界綻放
每過一個新關卡就能得到一份 LiShi之光，每 5 份會在 LiShi Bloom 揭開 60 個發現之一。

輕鬆好玩
• 沒有計時、生命或體力
• 大型牌、高對比、減少動態效果、讓卡住的牌變暗、柔化背景
• 可調整音效，也能關閉震動
• 可收集 4 種牌面主題和 3 種牌背

遊戲中獲得的金幣可以購買提示、復原和洗牌。金幣包與移除廣告等 App 內購買皆為選購，所有關卡都能免付費完成。

支援繁體中文、英文、希伯來文、日文、韓文、德文、法文、西班牙文、巴西葡萄牙文和俄文。`,
    notes: ['World and option names must match zh-Hant-TW.json.'],
  },
  ru: {
    title: 'Russian (ru)', locales: 'Google Play `ru-RU` · Apple `Russian`',
    name: 'LiShi Mahjong',
    short: 'Спокойные головоломки с фишками маджонга для 1 или 2 игроков. Создавайте поля.',
    subtitle: 'Вдвоём · Создать и поделиться',
    promo: 'Новое: Играть вдвоём – два игрока, один телефон, одно поле. И Студия раскладов – создайте расклад, решатель докажет, что его можно пройти, и поделитесь кодом.',
    keywords: 'вдвоём,семья,редактор,код,фишки,пасьянс,дзен',
    description: `LiShi Mahjong – спокойная головоломка с фишками маджонга: играйте одни, вдвоём с близким человеком или на раскладах, которые создаёте сами.

ИГРАТЬ ВДВОЁМ
Два игрока делят один телефон, одно поле и один лоток. Ходите по очереди, по одной фишке, и очищайте поле командой. Завершите пару, начатую партнёром, и получите бонус за командную работу. Без интернета и без аккаунтов: для пар, друзей, родителей и детей, бабушек, дедушек и внуков.

СТУДИЯ РАСКЛАДОВ
Создайте свой расклад: выберите одну из 10 форм, число фишек и слоёв. Перед игрой решатель проверит, что расклад можно пройти. У каждого расклада есть короткий код – попробуйте LS-5VSW-11BK. Отправьте свой другу, и он сыграет точно такой же расклад. В «Моих раскладах» помещается до 30 раскладов.

ЧЕСТНО, И ЭТО ДОКАЗАНО
Все 600 уровней проверены тем же решателем. Подсказка показывает следующий ход решения, найденного решателем, и предупреждает, если проверить не хватило времени. Если решатель доказывает, что оставшиеся фишки уже не убрать, игра сообщит об этом, а вернуться к последней решаемой позиции можно бесплатно.

КАК ИГРАТЬ
Нажмите на свободную фишку (на ней ничего нет, а её левая или правая сторона свободна), и она перейдёт в лоток. Две одинаковые фишки исчезают. Четыре фишки без пары заполняют лоток, поэтому важен порядок.

600 УРОВНЕЙ В 6 МИРАХ
Сад Авроры, Жемчужный берег, Хрустальный ноктюрн, Долина нефритового бамбука, Лотосовый дворец на закате и Деревня морозных огней – с многослойными полями, которые растут по пути.

ГОЛОВОЛОМКА ДНЯ
Каждый день новое поле, одинаковое для всех и доступное без интернета. Последние 30 дней остаются в архиве.

ВАШ МИР РАСЦВЕТАЕТ
Каждый новый уровень приносит огонёк LiShi. Каждые 5 огоньков открывают одно из 60 открытий в LiShi Bloom.

УДОБНО ИГРАТЬ
• Без таймеров, жизней и энергии
• Крупные фишки, высокий контраст, меньше движения, затемнение заблокированных фишек и мягкий фон
• Настройка звука; вибрацию можно выключить
• 4 темы фишек и 3 рубашки для коллекции

Монеты, заработанные в игре, покупают подсказки, отмены и перемешивания. Встроенные покупки (наборы монет, отключение рекламы) необязательны; каждый уровень можно пройти без оплаты.

Доступно на русском, английском, иврите, японском, корейском, немецком, французском, испанском, бразильском португальском и традиционном китайском.`,
    notes: ['World and option names must match ru.json.'],
  },
};

// What's New for ${VERSION} (App Store "What's New", Google Play release notes: 500 characters).
const WHATS_NEW = {
  "en": "300 new levels: every world now has 100. Each world's new levels continue where its level 50 leaves off and end a little harder. Your progress, stars and rewards moved with you, and you continue where you left off.\nFixed: closing and reopening the game reset the win streak and dropped a level in progress.",
  "he": "300 שלבים חדשים: בכל עולם יש עכשיו 100. השלבים החדשים בכל עולם ממשיכים מהמקום שבו שלב 50 נגמר ומסתיימים קצת יותר קשה. ההתקדמות, הכוכבים והפרסים שלכם עברו איתכם, וממשיכים מאיפה שהפסקתם.\nתוקן: סגירה ופתיחה מחדש של המשחק איפסו את רצף הניצחונות וביטלו שלב שהיה באמצע.",
  "ja": "新しいレベルが300個：どのワールドも100レベルになりました。各ワールドの新しいレベルはレベル50の続きから始まり、最後は少し難しくなります。進行状況・星・報酬はそのまま引き継がれ、続きから遊べます。\n修正：ゲームを閉じて開き直すと、連勝記録とプレイ途中のレベルが失われる問題を修正しました。",
  "ko": "새 레벨 300개: 이제 모든 월드에 100개의 레벨이 있어요. 각 월드의 새 레벨은 50레벨에서 이어지고 끝으로 갈수록 조금 더 어려워져요. 진행 상황, 별, 보상은 그대로 옮겨졌고 하던 곳에서 이어서 플레이할 수 있어요.\n수정: 게임을 닫았다가 다시 열면 연승 기록이 초기화되고 플레이 중이던 레벨이 사라지던 문제를 고쳤어요.",
  "de": "300 neue Level: Jede Welt hat jetzt 100. Die neuen Level jeder Welt setzen dort an, wo Level 50 aufhört, und werden zum Ende hin etwas schwerer. Dein Fortschritt, deine Sterne und Belohnungen sind mitgezogen, und du spielst dort weiter, wo du aufgehört hast.\nBehoben: Nach dem Schließen und erneuten Öffnen gingen die Siegesserie und ein angefangenes Level verloren.",
  "fr": "300 nouveaux niveaux : chaque monde en compte désormais 100. Les nouveaux niveaux de chaque monde reprennent là où s’arrête le niveau 50 et finissent un peu plus difficiles. Votre progression, vos étoiles et vos récompenses ont suivi, et vous reprenez là où vous vous étiez arrêté.\nCorrigé : fermer puis rouvrir le jeu remettait à zéro la série de victoires et effaçait le niveau en cours.",
  "es": "300 niveles nuevos: cada mundo tiene ahora 100. Los niveles nuevos de cada mundo siguen donde termina el nivel 50 y acaban un poco más difíciles. Tu progreso, tus estrellas y tus recompensas se movieron contigo, y sigues donde lo dejaste.\nCorregido: al cerrar y volver a abrir el juego se perdían la racha de victorias y el nivel en curso.",
  "pt-BR": "300 níveis novos: cada mundo agora tem 100. Os níveis novos de cada mundo continuam de onde o nível 50 termina e ficam um pouco mais difíceis no fim. Seu progresso, suas estrelas e recompensas foram junto, e você continua de onde parou.\nCorrigido: fechar e abrir o jogo de novo zerava a sequência de vitórias e descartava o nível em andamento.",
  "zh-Hant-TW": "新增 300 個關卡：現在每個世界都有 100 關。每個世界的新關卡從第 50 關結束的地方接續，最後會稍微難一點。你的進度、星星和獎勵都已一起移過來，可以從上次的地方繼續。\n修正：關閉後重新開啟遊戲，連勝紀錄會歸零、進行中的關卡會遺失的問題。",
  "ru": "300 новых уровней: теперь в каждом мире их 100. Новые уровни каждого мира продолжают с того места, где заканчивается уровень 50, и к концу становятся чуть сложнее. Ваш прогресс, звёзды и награды перенесены, и вы продолжите с того места, где остановились.\nИсправлено: после закрытия и повторного открытия игры сбрасывалась серия побед и пропадал начатый уровень."
};

// Google Play release notes for ${VERSION}: Play's production track went from 0.1.10 straight
// to 1.1.0 (1.0.0 was App Store only), so they also name Play Together and Board Studio.
const PLAY_NOTES = {
  "en": "New: Play Together – two players, one phone, one board, taking turns. Board Studio – build your own board, the solver proves it can be cleared, and you share it with a code. 300 new levels: every world now has 100, and your progress moved with you.\nFixed: closing and reopening the game reset the win streak and dropped a level in progress.",
  "he": "חדש: משחק בשניים – שני שחקנים, טלפון אחד ולוח אחד, בתורות. סטודיו לוחות – בונים לוח משלכם, הפותר מוכיח שאפשר לפנות אותו, ומשתפים אותו בקוד. 300 שלבים חדשים: בכל עולם יש עכשיו 100, וההתקדמות שלכם עברה איתכם.\nתוקן: סגירה ופתיחה מחדש של המשחק איפסו את רצף הניצחונות וביטלו שלב שהיה באמצע.",
  "ja": "新登場：ふたりで遊ぶ ― 1台のスマホ、1つの盤面を交代で。ボードスタジオ ― 自分で盤面を作ると、ソルバーがクリアできることを証明し、コードで共有できます。新しいレベルが300個：どのワールドも100レベルになり、進行状況はそのまま引き継がれます。\n修正：ゲームを閉じて開き直すと、連勝記録とプレイ途中のレベルが失われる問題を修正しました。",
  "ko": "새 기능: 함께 플레이 – 휴대폰 하나, 보드 하나로 두 사람이 번갈아 플레이해요. 보드 스튜디오 – 나만의 보드를 만들면 솔버가 클리어 가능함을 증명하고, 코드로 공유할 수 있어요. 새 레벨 300개: 이제 모든 월드에 100개의 레벨이 있고, 진행 상황은 그대로 옮겨졌어요.\n수정: 게임을 닫았다가 다시 열면 연승 기록이 초기화되고 플레이 중이던 레벨이 사라지던 문제를 고쳤어요.",
  "de": "Neu: Zu zweit spielen – zwei Spieler, ein Handy, ein Feld, abwechselnd. Brett-Studio – bau dein eigenes Brett, unser Löser beweist, dass es lösbar ist, und teil es per Code. 300 neue Level: Jede Welt hat jetzt 100, und dein Fortschritt ist mitgezogen.\nBehoben: Nach dem Schließen und erneuten Öffnen gingen die Siegesserie und ein angefangenes Level verloren.",
  "fr": "Nouveau : Jouer à deux – deux joueurs, un téléphone, une grille, chacun son tour. Studio de grilles – créez votre grille, le solveur prouve qu’elle est faisable, et partagez son code. 300 nouveaux niveaux : chaque monde en compte désormais 100, et votre progression a suivi.\nCorrigé : fermer puis rouvrir le jeu remettait à zéro la série de victoires et effaçait le niveau en cours.",
  "es": "Nuevo: Jugar juntos – dos jugadores, un teléfono, un tablero, por turnos. Estudio de tableros – crea tu propio tablero, el solucionador demuestra que tiene solución y lo compartes con un código. 300 niveles nuevos: cada mundo tiene ahora 100, y tu progreso se movió contigo.\nCorregido: al cerrar y volver a abrir el juego se perdían la racha de victorias y el nivel en curso.",
  "pt-BR": "Novo: Jogar juntos – dois jogadores, um celular, um tabuleiro, em turnos. Estúdio de tabuleiros – crie seu próprio tabuleiro, o solucionador prova que ele tem solução e você compartilha com um código. 300 níveis novos: cada mundo agora tem 100, e seu progresso foi junto.\nCorrigido: fechar e abrir o jogo de novo zerava a sequência de vitórias e descartava o nível em andamento.",
  "zh-Hant-TW": "新功能：雙人同樂 ― 一支手機、一個牌陣，輪流出手。牌陣工作室 ― 打造自己的牌陣，求解器會證明它可以清完，再用代碼分享。新增 300 個關卡：現在每個世界都有 100 關，你的進度也一起移過來了。\n修正：關閉後重新開啟遊戲，連勝紀錄會歸零、進行中的關卡會遺失的問題。",
  "ru": "Новое: Играть вдвоём – два игрока, один телефон, одно поле, ходы по очереди. Студия раскладов – создайте свой расклад, решатель докажет, что он проходим, и поделитесь им по коду. 300 новых уровней: теперь в каждом мире их 100, а ваш прогресс перенесён.\nИсправлено: после закрытия и повторного открытия игры сбрасывалась серия побед и пропадал начатый уровень."
};

const rows = [];
for (const [loc, t] of Object.entries(L)) {
  t.whatsNew = WHATS_NEW[loc];
  t.playNotes = PLAY_NOTES[loc];
  if (!t.playNotes || chars(t.playNotes) > 500) throw new Error(`${loc}: Play release notes missing or over 500`);
  if (!t.whatsNew) throw new Error(`${loc}: no What's New`);
  const f = {name: t.name, short: t.short, subtitle: t.subtitle, promo: t.promo, description: t.description, keywords: t.keywords, whatsNew: t.whatsNew};
  for (const k of Object.keys(LIMITS)) {
    const n = k === 'keywords' ? bytes(f[k]) : chars(f[k]);
    if (n > LIMITS[k]) throw new Error(`${loc}.${k} is ${n}/${LIMITS[k]}`);
  }
  if (/handcraft|designed by hand|30 discoveries|unlimited|always free|match-3/i.test(Object.values(f).join(' '))) throw new Error(`${loc}: forbidden claim`);
  const block = (s) => '```text\n' + s + '\n```';
  const md = `# LiShi Mahjong – Store listing: ${t.title}

> Version ${VERSION}. Generated by \`tools/store_listings/build_listings.js\` (edit the texts there, then rerun). Text inside each \`text\` block is the exact store text; counts in parentheses are script-computed (Unicode characters; Apple keywords in UTF-8 bytes). Non-English text is AI-translated: have a native speaker review it.

Suggested store locales: ${t.locales}.

## Google Play

### App name (${chars(t.name)}/30)
${block(t.name)}

### Short description (${chars(t.short)}/80)
${block(t.short)}

### Full description (${chars(t.description)}/4000)
${block(t.description)}

### Release notes ${VERSION} (${chars(t.playNotes)}/500)
${block(t.playNotes)}

## Apple App Store

### Name (${chars(t.name)}/30)
${block(t.name)}

### Subtitle (${chars(t.subtitle)}/30)
${block(t.subtitle)}

### Promotional text (${chars(t.promo)}/170)
${block(t.promo)}

### Description (${chars(t.description)}/4000)
${block(t.description)}

### Keywords (${bytes(t.keywords)}/100 bytes)
${block(t.keywords)}

### What's New in ${VERSION} (${chars(t.whatsNew)}/4000)
${block(t.whatsNew)}

## Notes for native reviewer

${t.notes.map((n) => '- ' + n).join('\n')}
`;
  fs.writeFileSync(path.join(OUT, `${loc}.md`), md);
  rows.push(`${loc}: short ${chars(t.short)}, subtitle ${chars(t.subtitle)}, promo ${chars(t.promo)}, desc ${chars(t.description)}, keywords ${bytes(t.keywords)}B, what's new ${chars(t.whatsNew)}`);
}
console.log(rows.join('\n'));
