# Stabilní evidence, příprava a doptávání Aidy

Implementace 18. října 2026 na tomto Macu; původní Iris se nemění. Navazuje na [P1](work-knowledge-pilot-verification.md).

## Stabilní vazba

Connect 0.8.0 vrací podepsanému IrisRead na existující `status` a v rutinních normalizovaných dávkách `bindingRef`. Jde o doménově oddělený SHA-256 otisk hashe ověřené identity a kanonického potvrzeného vlastního workspace. Neobsahuje raw identitu, adresu prostoru, kódy, token ani cookie a nelze jím autorizovat požadavek. Nezávisí na relaci, buildu, čase nebo MFA. Jiný účet/prostor dává jinou referenci.

Výpočet probíhá jen nativně po spárování a ověření relace. Jádro porovná referenci ze stavového helperu a všech dávek. Změna znamená `scopeReviewRequired` a awaitingBinding, nikoli sloučení dat nebo nový MFA pokus. Reference se Aidě nepředává. Sanitizovaný read-verification.json a diagnostické piloty zůstávají jen stavy/kontrolami/počty. Nové +4U commandy ani cíle nevznikly.

Stabilita nenahrazuje místní souhlasy s novým podpisem. Při dalším přihlášení stejného účtu se čtení obnovuje pouze podle již existující člověkem povolené volby a kontroly podpisů, identity a prostoru. Kalendář a obsahové kontrakty se ověřují pro novou relaci znovu.

## Zachování historie

Před aktualizací ověřil starý nativní helper shodu aktuální epochy s uloženým P1; soukromě se zaznamenala jako `legacy_scope_verified`. Není to vyrobený lidský souhlas. Ověřená záloha `prebinding.sqlite` zachovává stav před převodem.

Nová aplikace při startu odvodí referenci z veřejných metadat předchozího čtecího souhlasu. Po novém místním párování ji vrátí jako `previousBindingRef` pouze při přesné shodě s aktuálně ověřeným účtem/prostorem. Nečte starý token a nepřebírá starý souhlas s podpisem.

Převod vyžaduje obě podmínky: ověřenou starou epochu a nativní shodu původní/aktuální vazby. Transakčně změní jen scope položek; zachová interní ID, verze, kroky, tvrzení, vstupy a audit. Upsert hledá přesnou stabilní identitu, nikoli podobný název nebo obsah. Vlastní uuDwRecord zůstává odlišený od obsahového artefaktu; neexportované ID elementární aktivity se nevymýšlí.

## Večerní a ranní příprava

Rozvrh se nemění: 18:00 a 6:40 pro předání Aidou v 7:00, pracovní dny Europe/Prague. Nová automatizace nevzniká. `workflow.run_job` po schváleném čtení kontroluje stabilní vazbu a volá `knowledge_preparation.sync` nad stejným balíčkem; není potřeba druhá kompletní dávka pro pilot.

Kurátorovanou oblastí je zatím Companion. Tři historické poznámky se čtou pouze z povolených cest; změna hashe vyžaduje obsahovou revizi. Pokud pilotní schůzka není v cílovém dni, znalosti se nepřipojí k jiné podle názvu. Vlastní vazba se kontroluje i v takovém dni.

Evidence se aktualizuje transakčně. Příprava rozlišuje historická sdělení, interpretace a návrhy rozhodnutí. Aktuální přípravu cituje z konkrétní stránky aktuálního zdroje. Karta prochází stejným validátorem skutečných citací a vazby na položku jako jiné analýzy. Chybějící citace nebo změněný zdroj připravenou kartu nepovolí.

Kontext vstupuje do hashe balíčku a analytický vstup obsahuje `preparedContext`. Stará analýza se nepřenáší na změněné znalosti nebo jiný účet. Při publikaci se znalostní karta spojí s ostatními kartami dosavadní analýzy. Částečné vstupy zůstávají missing. Chyba revize má viditelné varování a nevytváří osobní úkol. Není to úplná migrace všech témat ani přijetí rozhodnutí z hlasu.

## Doptávání Aidy

Šestý nástroj `iris_get_preparation_detail` přijímá pouze `id` aktuální položky a `topic`: overview, options, recommendation, sources, missing nebo task. Vrací připravený přehled, varianty, návrh Iris, původ informací, chybějící vstupy nebo související úkol.

Aida jej používá místo přístupu k databázi, souborům nebo přímého +4U. Není tu obecný textový příkaz, URL, cesta, skript, modelové volání, zápis nebo MFA. Jde o doptávání nad připraveným podkladem; nový výzkum nebo další analýza zůstává přiznanou mezerou. Navazuje nyní implementovaná [fronta dopracování a rozhodnutí MCP 0.5.0](aida-work-handoff.md); tato kapitola zachycuje původní šestinástrojový krok.

Výstup je v jediném `.iris-runtime/briefing-details.json` do 64 KiB. MCP kontroluje vlastníka, práva, hardlinky/symlinky, velikost, striktní schéma a vzory citlivých hodnot. Sandbox povoluje jen tento druhý publikovaný soubor. Databáze, snapshoty, historické poznámky a Keychain zůstávají nepřístupné.

Datum, čas generování a čas zdrojů detailu musejí souhlasit s briefingem. ID musí být v jeho agendě/prioritách, jinak přijde detailNotPrepared. Nesouhlasný podklad se nevydává. Stáří nad 30 minut přechází jako stale; readiness a missing ukazují neúplnost. Výstup SDK se znovu validuje i při chybách.

Po restartu hosta obnovit Iris Local přes Spravovat → Znovu načíst nástroje; očekává se šest, bez nového pluginu/tunelu/klíče. Skutečné použití Aidou prokáže až její volání nebo lidské potvrzení, nikoli místní katalog.

## Ověření a nasazení

Prošlo 70 nativních, 35 Python a 17 MCP testů včetně OS zákazu sítě, procesů a soukromých souborů. Test přípravy pokryl prepare i morning, citaci a detail. Oddělený hardened build byl sestavený a podepsaný před skutečnými údaji.

Automatická kontrola odmítla ukončení běžící Connect. Miloš poté schválil nasazení a restarty. Správce ověřil busy=false, ukončil 0.7.7, zachoval bundle v build/backups/Iris Connect.0.7.7-before-stable-binding.app a spustil 0.8.0. Restartoval se MCP host a pracovní proces. Rozvrh, Mini a původní Iris se neměnily.

Miloš potvrdil nové místní souhlasy i přihlášení a po obnovení pluginu vidí šest nástrojů. Živý běh načetl 24 materiálů; časy 18. října Europe/Prague: úkoly 23:09:07, kalendář 23:09:33, obsah 23:11:53. V 23:12:06 byl publikovaný briefing na 19. října s pěti obsahovými analýzami, včetně znalostní karty nahrávání. Stav je partial, protože podklady nejsou úplné.

Převod původní evidence proběhl jednou: dvě položky se stejnými interními ID, sedm tvrzení, tři captures a čtyři verze. Obě původní verze zůstaly beze změny; další dvě zachycují převod scope. Ověření zálohy a obnovení všech řádků prošlo.

Skutečný sandboxovaný MCP vrátil pro pilotní schůzku témata options, recommendation, sources a task: vždy jednu sekci, jednu citaci a čtyři přiznané mezery. Cloudové volání Iris Local současně vrátilo aktuální pondělní briefing se znalostní kartou. Miloš následně předal odpověď hlavní Aidy: načetla briefing i detail pilotní schůzky, popsala tři varianty, doporučení Iris, původ a váhu zdrojů i chybějící vstupy. Uvedla skutečné časy a souběh se StandUpem; historický DRAFT nevydávala za rozhodnutí a přihlášení nespustila. To je lidsky doložený průchod hlavní Aidou, oddělený od místního technického testu.

Po druhém běžném přihlášení, které Miloš sám spustil a dokončil bez změny prostoru/párování, stav helperu potvrdil novou relaci se stejnou stabilní referencí. Živé `tasks.listActive` v 23:16:43 Europe/Prague vrátilo obě pilotní položky; přesná identita obou odpovídala původním interním ID. Upsert úkolu zachoval čtyři verze celkem, dvě položky a sedm tvrzení; duplicity nevznikly. Následná kontrola zálohy i obnovení všech řádků prošly.

Tato poslední kontrola obnovila jen aktivní úkoly a ověřila vazbu i historii. Nevydává se za novou kompletní dávku schůzek a podkladů; tři captures a časy publikovaného briefingu zůstávají podle předchozího skutečného čtení. První plánované ranní doručení 19. října a případné upozornění na MFA stále čekají na samostatné provozní ověření.
