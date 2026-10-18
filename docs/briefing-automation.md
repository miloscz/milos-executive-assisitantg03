# Automatická příprava a ranní obnova

**Aktuální stav večer 18. října:** oprava Elementary je v 0.7.7 živě ověřená včetně textu kontrolní schůzky. Nový pondělní briefing je přes Iris Local current/partial: 14 karet, pět obsahových analýz a sedm ověřených citací. Zdroje agendy jsou od 21:39:23, dávka podkladů skončila 21:42:39 Europe/Prague. Neúplné převody, nenačtené přílohy a další schůzky bez použitelného výňatku zůstávají označené. Rozvrhy a omezené MCP se neměnily. Podrobnosti jsou v [záznamu ověření](iris-connect-read-verification.md).

Miloš 18. října 2026 zadal automatizaci a potvrdil časy **18:00 a 7:00 v pracovní dny, Europe/Prague**. V 18:00 se připravuje následující pracovní den (v pátek pondělí), v 7:00 dnešní den. Víkend není automaticky pracovní den; státní svátky zatím nemají vlastní kalendář.

Iris vlastní práci, podklady a frontu. Aida pouze čte připravený výstup a řeší komunikaci včetně upozornění na MFA. Naplánovaný běh, obnovení procesu ani nové čtení nejsou souhlasem s MFA. Po přihlášení se musí bezpečně obnovit čtecí vazba pouze ke stejnému potvrzenému účtu/prostoru a stejnému podepsanému klientovi.

## Schválené společné rozšíření zdrojů

Miloš 18. října schválil společnou sadu s výslovným doplněním `keyTask` a `request`: „Tak tam přidej ještě keyTask i request. Jinak schvaluji.“ [Záznam schválení](../policies/iris-connect-briefing-sources-v1.approval.json) váže původní posouzený hash, přesnou změnu i hash výsledného souboru. [Společná politika](../policies/iris-connect-briefing-sources-v1.draft.json) zůstává návrhovým specifikačním souborem; runtime se aktivuje až podepsanou implementací a piloty. Již schválená politika DW a kalendáře zůstává beze změny. Původní užší návrh pouze pro Elementary Management schválený nebyl.

| Čtení | Účel a omezení |
| --- | --- |
| GET meeting/load v Elementary Management | Detail vlastní nadcházející schůzky vybrané přes čerstvý záznam vlastního DW nebo ověřeného kalendáře. |
| GET meeting/page/load v Elementary Management | Jedna hlavní stránka této schůzky s přípravou a zápisem. Identifikátory pouze z její předchozí odpovědi. |
| GET ai/ecc/document/getMetadata v ManagementKit | Typ, název a seznam stránek vybrané entity `meeting`, `document`, `keyTask` nebo `request`. OID pouze z ověřeného pracovního zdroje. |
| GET ai/ecc/panel/getContent v ManagementKit | Text sekcí hlavního panelu vybrané stránky téže entity; nejvýše čtyři stránky, hlavní první. |

Politika připouští identifikátor pracovního záznamu; současná implementace je užší: obě pevné nativní operace nemají argumenty a kandidáty vybírají samy. Agent nezadává URL, workspace ani obecný uuCommand. Proxy ověří přesný host, aplikaci, identifikátory, typ entity a příslušnost každé stránky. Aida nové přímé čtecí nástroje ani přístup k Macu nedostává: dál čte jen připravený výstup přes omezené Iris MCP.

Na běh nejvýše 16 schůzek v příštích 14 kalendářních dnech a osm dokumentových podkladů (`document`, `keyTask`, `request`) k vlastním aktivním úkolům či rozhodnutím. Osm dokumentů zahrnuje i přímo odkazované dokumenty, keyTask a request ManagementKit z již povolených kořenových podkladů. Pro ty platí **jediný krok odkazu**: z navazujícího dokumentu se dál neprochází. Nejde o plošné hledání v teritoriu. Metadata stránek mohou obsahovat další stránky; při překročení limitu čtyř nebo vynechání skrytých stránek se výstup označí jako neúplný.

Odpověď nejvýše 4 MiB, obsah ManagementKit nejvýše 20 000 znaků na sekci a 80 000 na stránku, celkem 160 000 na entitu. Nejvýše 120 pokusů o požadavek a deset minut na běh, původní limit 30 pokusů za minutu a souběh dva. Vyčerpání limitu označí neúplnost; nevybrané záznamy zůstávají v pracovním snapshotu. Samostatný pokračovací kurzor pro zbytek zdrojové dávky zatím implementovaný není. Zůstávají zakázané přílohy, další aplikace a typy entit, další úrovně odkazů, zápisy, tokenové výstupy a vykonávání vložených komponent nebo příkazů. Odkaz na PDF, tabulku, vložený obsah či jiný nepřečtený podklad zůstane viditelně chybějícím vstupem.

Elementary kontrakty jsou doložené čtecí částí původního adaptéru, který se nespouští. Aktuální ManagementKit ECC kontrakty byly 18. října přečtené přímo v primární specifikaci: [metadata](https://uuapp.plus4u.net/uu-bookkit-maing01/67e1f3330b0140b2b886057618bc82ce/book/page?code=86054184), [obsah panelu](https://uuapp.plus4u.net/uu-bookkit-maing01/67e1f3330b0140b2b886057618bc82ce/book/page?code=80057086). Schéma instalovaného čtecího nástroje ECC výslovně podporuje entity `document`, `meeting`, `keyTask` i `request`; proxy musí očekávaný typ sama kontrolovat. Specifikace [meeting/loadByOid](https://uuapp.plus4u.net/uu-bookkit-maing01/67e1f3330b0140b2b886057618bc82ce/book/page?code=76983610) je označená jako zastaralá; nové ECC čtení ji nepotřebuje. Technickou specifikaci četl implementační agent, nikoli Aida; tím není povolené obcházet Iris Connect při čtení pracovních podkladů.

Po schválení přesného souboru a syntetických testech musí nativní pilot ověřit jednu vlastní schůzku každého systému a po jednom vlastním podkladu `document`, `keyTask` a `request`, pokud takový je v aktuálních vlastních zdrojích. Chybějící typ zůstane samostatně zavřený. Pilot vrací pouze pevné kontroly a počty; běžné normalizované texty se povolí až po splnění kontraktů. Klientská tajemství ani přihlašovací údaje se kvůli tomu nečtou.

## Co ještě chybí do ranního provozu

| Krok | Kritérium dokončení |
| --- | --- |
| Schválené zdroje a nativní adaptéry | Schválená přesná politika, negativní testy cíle a parametrů, pilot pro všech pět zdrojových kontraktů, žádná libovolná síťová cesta pro Aidu. |
| Trvalá fronta a obnova po MFA | Běh přežije restart, nezdvojí práci a po skutečně dokončeném přihlášení naváže; sám nikdy nevolá `noticeSent` ani `start`. |
| Obnova čtecího párování | Samostatný místní souhlas člověka; po novém loginu stejná identita, potvrzený prostor i podpisy aplikace a klienta. Změna účtu vše zneplatní. Kalendář se znovu ověří. |
| Obsahová příprava | Ke schůzce cíl, agenda, otevřené body a otázky; k rozhodnutí varianty, doložená fakta, rozpory, doporučený další krok a přesný požadovaný vstup Miloše. Každé tvrzení dohledatelné ve zdroji. Samotný checklist není připravené rozhodnutí. |
| Večerní a ranní běh | 18:00 další pracovní den, 7:00 dnešní den v Europe/Prague; pátek míří na pondělí. Ráno se načtou aktuální zdroje a zapracují změny oproti večeru. Oba běhy a tiché dokončení čekající analýzy jsou uložené jako aktivní heartbeat automatizace tohoto chatu; přesné identity a provozní postup jsou v [runbooku](briefing-runbook.md). |
| Pravidelné předání Aidou | Ověřená uložená rutina hlavní Aidy, která načte výstup přes Iris Local a oznámí čekání na MFA. Doručení textem již funguje na pokyn; automatické ranní doručení a hlasový rozhovor ještě ověřené nejsou. |
| Aktuálnost a chybějící vstupy | Datum briefingu a skutečné časy načtení; neúplné stránky, zkrácení, přílohy a chybějící dokumenty uvedené konkrétně. Starý výstup nepřeznačit novým časem. |

Samostatně zbývá čtení PDF a Office příloh, jiných typů ManagementKit (např. `email` a `portal`), návazných dokumentů mimo schválený jeden krok a zdrojů v dalších aplikacích. Pro podklady, které takové vstupy vyžadují, nelze bez jejich doplnění tvrdit obsahovou úplnost. Tyto konektory se nepovolují skrytě společně s textovým čtením. Pravidla pro rezervace času, zápisy rozhodnutí, Signal s Adélou a rotaci tunelového klíče mají vlastní implementační kroky; toto rozšíření nezavádí zápisy.

## Pořadí implementace

1. Společný čtecí návrh je schválený; implementovat a synteticky ověřit nativní kontrolu zdrojů a obnovení čtecího párování. Dokončit sestavení před novými místními souhlasy.
2. Nasadit jednou, s člověkem ověřit souhlasy a MFA, provést pevný nativní pilot a normalizovat povolené podklady.
3. Dokončit frontu, přípravu s odkazy na konkrétní podklady a omezený výstup MCP. Provozní workflow, fronta a přípravné karty jsou zapojené do nasazeného MCP 0.3.0; první živý výstup byl ověřený místně i přes cloudový Iris Local.
4. Ověřit celý cyklus nad skutečným následujícím dnem a přerušení kvůli expiraci bez automatického MFA. Potom zapnout potvrzené časy a ověřit hlavní Aidu jako pravidelný doručovací kanál.

## Provozní podmínky

Mac musí být zapnutý a přihlášený do macOS; zamčení je jiný stav než uspání nebo odhlášení. Při expiraci +4U zůstane uložená práce čekat. Žádný agent neprovádí automatické MFA a nevydává starý nebo neúplný briefing za aktuální.


## Stav po místním ověření – 18. října 2026

Connect 0.7.1 má člověkem obnovené souhlasy, MFA a čtecí párování. Fronta automaticky navázala na čekající úlohu po jeho přihlášení. Pilot ověřil všechny čtyři typy ManagementKit: meeting (1 stránka), document (1), keyTask (4) a request (1). Elementary meeting zůstává `schemaMismatch`, a tedy zavřený pro provozní textové čtení. Samotná příčina této chyby není prokázaná; nepovolovalo se ignorování serverových warnings ani alternativní síťová cesta. Další diagnostika tohoto adaptéru zůstává konkrétní otevřenou opravou.

První běh pro pondělí 19. října načetl 9 podkladů / 19 stránek, publikoval 14 přípravných karet a dvě obsahové analýzy s pěti ověřenými citacemi. Kalendář je verified (11 bloků, 3 priority, 2 souběhy). Nejstarší agendový zdroj byl skutečně načten v 20:23:56 Europe/Prague, zdrojové podklady do 20:26:25. Skutečné sandboxované stdio i cloudové Iris Local vrátily stejný nový výstup jako current a workflow partial. Část dokumentů obsahuje nepodporované vložené komponenty a hlavní analytický výňatek jednoho podkladu je zkrácený; tyto mezery jsou výslovně označené. Výstup není úplnou přípravou všech schůzek.

Miloš předal potvrzení Aidy o uložené jediné rutině Po–Pá v 7:00/18:00 Europe/Prague od 19. října, s doručením do hlavního chatu a pouze Iris Local. Aida následně přislíbila i opakování kontroly starých zdrojů po třech minutách, nejvýše dvacet minut. První skutečný plánovaný běh, nové obnovení čtecí vazby po další MFA a hlasový rozhovor se ještě musí provozně ověřit. Nejde o doklad již uskutečněného ranního doručení.

Ověření implementace: 57 nativních syntetických testů, 10 testů jádra, 15 testů MCP včetně skutečného OS omezení sítě/souborů/procesů a 8 testů správce spuštění včetně ochrany proti nečinnému uspání při AC. Fronta testuje restart, duplicity a zákaz startu MFA; živé přihlášení potvrzoval člověk. LaunchAgenty Connect, MCP a pracovní fronty jsou nyní spuštěné. Žádná automatizace ani proces jádra nemá cestu k hodnotám přihlašovacích údajů.


Místní provoz doplňuje samostatná ochrana proti nečinnému uspání pouze při napájení ze sítě, protože výchozí uspání bylo nastavené na jednu minutu. Nemění systémová nastavení a nezabraňuje zamčení/vypnutí displeje. První živá kontrola prokázala uvolněnou ochranu při baterii. Po připojení nabíječky byla ověřená také skutečná aktivní ochrana PreventUserIdleSystemSleep vlastního procesu Iris při AC; všechny čtyři služby běžely. [Postup a odstranění](briefing-runbook.md#dostupnost-tohoto-macu).


## Probíhající oprava Elementary – večer 18. října

Jednorázová schválená diagnostika zjistila technický název unsupportedKeys a byla odstraněná z kódu i obou dočasných bundlů 0.7.3. Živé pokusy 0.7.4 a 0.7.5 čtení stránky stále odmítly; čtyři typy ManagementKit dál fungují. 0.7.6 přidává dokumentovanou strukturu paramMap.unsupportedKeyList, kterou dosavadní parser neznal. Je sestavená a nasazená, ale čeká na místní souhlasy a živý pilot. Do jeho úspěchu Elementary texty zůstávají blokované a předchozí částečný briefing se nesmí vydávat za novou úplnou přípravu. Přesné důkazy a omezení jsou v iris-connect-read-verification.md.
