# Architektura Iris třetí generace

Stav k 18. říjnu 2026. Produktová pravidla níže vycházejí z dohody s Milošem. Technologie, názvy rozhraní a provozní parametry jsou návrhem realizace, pokud nejsou výslovně označeny jako potvrzené. Tento dokument neaktivuje přístupy, automatizace ani dosud neschválené uuCommandy.

## Účel a měřítko úspěchu

Iris má připravovat schůzky, podklady k rozhodnutí a konkrétní řešení úkolů. Ranní briefing má být rozhovorem nad již připravenou prací. Největší překážkou včasného dokončování úkolů jsou schůzky a operativa, které vytlačují soustředěnou práci.

Systém proto plánuje zpětně od termínů, začne vlastní přípravu s předstihem a rezervuje čas pro Milošův nezastupitelný příspěvek. Po rozhodnutí pokračuje v práci a ověřuje výsledek.

Úspěch se hodnotí podle včasného posunu důležitých závazků, připravenosti podkladů a ušetřené Milošovy práce. Počet poznámek, nalezených podnětů nebo spuštěných agentů není cílovou metrikou.

## Potvrzená produktová rozhodnutí

| Oblast | Dohodnuté pravidlo |
| --- | --- |
| Jméno komunikační agentky | Aida — AI Dialogue Assistant; postavená na platformě Dot. České oslovení: Aido. |
| Komunikace | Aida je hlavní rozhraní pro rozhovor, ranní briefing a rozhodnutí, včetně hlasového hovoru při cestě autem. |
| Trvalá paměť | Znalosti, rozhodnutí a stav práce existují mimo konverzaci s Aidou a spravují je agenti Iris. |
| Zdroj práce | Úkoly a schůzky v +4U jsou primárním zdrojem pracovní agendy. |
| Další zdroje | Nová položka mimo +4U musí být uvážená; pouhé zachycení informace nesmí automaticky vytvořit úkol. |
| Příprava | Agenti připravují řešení s předstihem a oddělují vlastní práci od potřebného vstupu Miloše. |
| Volný čas | Iris smí sama vytvářet pracovní rezervace podle dohodnutých pravidel. Konkrétní časová pravidla ještě nejsou stanovena. |
| Vlastní rezervace | Iris smí rovnou přesouvat Milošovy vlastní rezervace bez dalších účastníků. Musí být určeno, které položky jsou skutečně přesunutelné rezervace. |
| Společné schůzky | Záměr přesunu schválí Miloš přes Aidu; domluvu s dalšími účastníky řeší Adéla Babicová přes Signal. |
| Přístup k +4U | Nativní macOS proxy drží Access Code 1 a 2 v klíčence a nevydává je agentům. Registrace nové aplikace není pro Miloše dostupná. |
| MFA | Potřebné přihlášení se oznámí přes Aidu. MFA potvrzuje Miloš. Po zmeškaném pokusu lze na jeho pokyn spustit nový. |
| Operace proxy | Proxy může provádět čtecí i zapisovací operace, ale jen prostřednictvím výslovně schválené sady uuCommandů a pravidel parametrů. Čtecí sada iris-connect-read-v1 byla schválená 18. října 2026; pracovní zápisy zatím povolené nejsou. |
| Cílový projekt | Nová Iris se buduje a bude udržována v tomto repozitáři. |
| Provozní počítač | Po výpadku správy Mini Miloš rozhodl nejprve rozjet provoz na tomto Macu; přenos na Mini dokončíme později. Místní host dostane samostatný soukromý tunel. Aida bude používat vždy jen výslovně zvolený omezený plugin. |

Aida přirozeně zpracovává obsah rozhovoru a může mít vlastní produktovou paměť. Požadavek znamená, že rozhodující stav a znalosti musí být dostupné a přenositelné i bez ní; neznamená záruku, že si Aida nic neuchová.

## Složky systému a jejich odpovědnosti

| Složka | Odpovědnost | Co předává dál |
| --- | --- | --- |
| Aida | Vede rozhovor, vysvětluje připravené varianty, zachycuje rozhodnutí a požadavky. | Strukturované pokyny, rozhodnutí a schválení navázané na konkrétní podklady. |
| Rozhraní Iris | Zpřístupňuje Aidě potřebné informace a operace přes MCP/plugin. | Ověřené výsledky, identifikátory dlouhé práce a významné události. |
| Koordinátor | Hlídá priority, termíny, závislosti, připravenost podkladů a Milošovu kapacitu. | Zadání agentům, návrhy změn plánu a požadavky na rezervace. |
| Znalostní agent | Spravuje fakta, zdroje, rozhodnutí, vazby a rozpory. | Kontextové balíčky a navržené aktualizace znalostí. |
| Agent pro schůzky | Připravuje cíl jednání, historii, otevřené závazky, otázky a doporučení. | Přípravu na schůzku a po jednání kandidáty na aktualizaci znalostí a závazků. |
| Agent pro řešení úkolů | Vytváří analýzy, dokumenty, návrhy odpovědí a varianty řešení. | Konkrétní výstupy, jejich ověření a potřebná rozhodnutí Miloše. |
| Provozní služba | Ukládá stav, spouští práci, hlídá limity, obnovuje přerušené běhy a vynucuje pravidla. | Frontu práce, audit změn a události pro Aidu. |
| Iris Connect | Přihlašuje k +4U, drží tajné údaje a vykonává pouze povolené operace. | Data, stav přihlášení a ověřený výsledek provedené operace. |
| Signal adaptér | Doručuje povolené požadavky Adéle a přiřazuje odpovědi k požadavkům. | Stav koordinace konkrétního přesunu. |

Jde o logické role. První verze může provozovat jejich běhy na jednom počítači a sdílet modelový runtime. Každý běh dostane vlastní zadání, relevantní kontext a omezené nástroje. Podklady k rozhodnutí jsou společnou schopností procesních agentů, zatím ne samostatnou rolí.

## Navržená technická realizace

- Nativní Swift aplikace Iris Connect v horní liště macOS, macOS Keychain pro tajné údaje.
- TypeScript/Node.js pro provozní službu, plánování, adaptéry a rozhraní pro Aidu.
- SQLite na jednom provozním hostu pro pracovní stav, frontu, schválení a události. Více počítačů nepřistupuje přímo ke sdílenému databázovému souboru.
- Markdownový vault pro čitelné znalosti a výstupy, doplněný obnovitelným vyhledávacím indexem.
- Adaptér nad současným Claude Code runnerem jako první varianta běhu agentů. Konkrétní modely, dostupnost a provozní limity se ověří při implementaci.
- Existující Iris dashboard jako výchozí bod pro kontrolu připravených podkladů, blokací a provozu.
- První přihlášení a čtecí pilot proběhly na současném Macu. Navazuje schválená příprava Macu mini, včetně přihlašování při zamčení a soukromého MCP. [Provozní postup](mac-mini-deployment.md).

Git verzování kódu a znalostí nebude podmínkou dokončení každé provozní operace. Provozní databáze a případné fronty budou zálohovány samostatně; nebudou synchronizovány přes Git.

## Data a zdroje pravdy

| Druh informace | Autorita a uložení |
| --- | --- |
| Oficiální úkoly a schůzky | +4U; lokálně se ukládá synchronizovaný obraz se stabilním identifikátorem a časem úspěšného načtení. |
| Stav Milošovy části úkolu | Odpovídající elementární aktivita v +4U, nikoli pouze celkový stav aktivity. |
| Interní příprava a běhy agentů | Provozní databáze Iris. |
| Fakta, souvislosti a rozhodnutí | Spravovaný vault a odkazované původní zdroje. Fakt, odhad a kandidát na rozhodnutí jsou rozlišeny. |
| Procesní know-how | Verzionované postupy, šablony a pravidla agentů v projektu. |
| Schválení | Trvalý záznam navázaný na konkrétní návrh, parametry a verzi podkladu. |
| Přihlašovací údaje | Pouze Iris Connect a macOS Keychain; nevstupují do agentních kontextů. |

Základní entity: pracovní položka, zdrojový záznam, krok přípravy, výstup, požadavek na rozhodnutí, rozhodnutí, pracovní rezervace, žádost Adéle, schválení, běh, checkpoint synchronizace a událost k doručení.

Pracovní položka obsahuje požadovaný výsledek, termín, význam a dopad odkladu, závislosti, odhad přípravy, potřebný Milošův vstup, jeho délku a nejpozdější čas, stav podkladů, navázanou rezervaci a kritérium dokončení. Odhady jsou opravitelné a odlišené od závazných termínů.

Každý znalostní záznam má správce. Agenti navrhují změny a služba je validuje a ukládá; nesmějí současně nekontrolovaně přepisovat stejné soubory. Vyhledávací index ani text generovaného briefingu není autoritou pro stav úkolu.

## Vstupní filtr a inbox

Synchronizované úkoly z +4U vstupují do pracovní evidence bez vytváření další kopie při každé změně. Schůzka se stává položkou kalendáře; přípravné kroky patří pod ni, pokud přípravu skutečně potřebuje.

Informace ze Signalu, dokumentů a rozhovorů nejprve doplní znalosti nebo existující pracovní položku. Nový kandidát mimo +4U musí doložit potřebný výsledek, vlastníka, vazbu na priority, důvod aktuálnosti a kontrolu duplicity. Výslovné zadání Miloše má přednost.

Nejasní kandidáti zůstávají v oddělené frontě s pravidlem revize a expirace. Samotné stáří nebo opakované nalezení je neposouvá do Milošova inboxu. Přetečení synchronizace, chyby provozu a interní kroky agentů nejsou osobní úkoly Miloše.

## Příprava a denní cyklus

1. Průběžně načítat změny úkolů, kalendáře a podkladů. Periodické čtení je výchozí varianta, pokud zdroj neposkytuje ověřený mechanismus událostí.
2. Posoudit důležité závazky v horizontu několika týdnů a rozpracovat nejbližší kroky. Konkrétní horizonty a frekvence jsou konfigurovatelné.
3. Od termínu zpětně naplánovat dokončení, Milošův příspěvek, externí vstupy a vlastní přípravu s rezervou.
4. Předchozí pracovní den připravit následující den a rozběhnout delší práci. Ráno aktualizovat změny, nikoli začínat veškerou přípravu od nuly.
5. Z připravených výstupů sestavit krátkou agendu pro Aidu: rozhodnutí, potřebné osobní kroky, pracovní bloky, důležité schůzky a podstatné výjimky.
6. V rozhovoru procházet jedno téma po druhém. Rozlišit rozhodnutí vhodná pro hlasový rozhovor od činností vyžadujících obrazovku a soustředění.
7. Rozhodnutí uložit, potvrdit převzetí a navázat další prací. Při přerušení hovoru zachovat, co již bylo uzavřeno a co ještě čeká.

Příprava na schůzku obsahuje účel a očekávaný výsledek, historii, otevřené závazky, doporučené body a otázky. Podklad k rozhodnutí obsahuje otázku, varianty, dopady, doporučení, zdroje a nejistoty. Připravené řešení úkolu je konkrétní artefakt s uvedením ověřených částí a zbývajících kroků.

## Kalendář a spolupráce s Adélou

Volný čas se počítá ze všech blokujících záznamů kalendáře, včetně osobního volna. Neznámá klasifikace nebo neaktuální data nejsou důkazem volného času.

Automatická rezervace má vazbu na úkol, jasný účel, očekávaný výsledek a délku. Před zápisem se znovu ověří dostupnost a po zápisu se ověří vznik záznamu. Ručně odstraněnou rezervaci systém bez dalšího neposkládá znovu.

Přesouvání vlastních rezervací vyžaduje spolehlivou klasifikaci: vlastnictví, skuteční účastníci, typ položky a příznak pevného závazku. Nepřítomnost účastníků v neúplném výpisu nestačí. Přesunutí musí respektovat termíny a zachovat smysl bloku; omezení četnosti přesunů se nastaví tak, aby kalendář neustále neměnil podobu.

U společné schůzky Aida získá schválení konkrétního záměru. Iris předá Adéle přes Signal identifikaci schůzky, důvod, vhodná náhradní okna a termín vyřešení. Žádost se sleduje odděleně od Milošova inboxu. Adélina odpověď se přiřadí ke konkrétní žádosti; nejednoznačná odpověď neznamená dokončení.

Odeslání zprávy není provedený přesun. Do ověření změny v +4U zůstává původní termín součástí plánu. Při rozporu mezi odpovědí a kalendářem se uloží stav čekající na ověření. Doručování, opakování a případné připomenutí Adéle mají vlastní pravidla; automatické urgence zatím nejsou dohodnuté.

Pracovní hodiny, délky bloků, přestávky, rezerva na operativu, předstih změn a zacházení s pevnými osobními rezervacemi se teprve dohodnou. Při nedostatku kapacity Aida předloží konkrétní kompromis; systém nesmí vydávat nesplnitelný plán za splnitelný.

## Iris Connect a přihlašování

Access Code 1 a 2 se zadávají výhradně v nativním okně aplikace. Ukládají se do klíčenky s přístupem omezeným na aplikaci. Agentům se nevystavuje čtení kódů, tokenů, cookies ani autorizačních hlaviček. Tajné údaje se neposílají do logů, repozitáře nebo diagnostických výstupů; aplikace je používá pouze vůči určenému přihlašovacímu systému a povoleným službám +4U.

Registrace nového OIDC klienta není dostupná. Místní prototyp živě ověřil Authorization Code + PKCE s existujícím klientem převzatým interně z Iris, validaci tokenu a čtení identity. Ve verzi 0.2.2 uživatel potvrdil průchod s automatickou volbou Plus4U Access a pouze MFA na telefonu. Podpora refresh tokenů ani přenos relace po restartu tím ověřené nejsou; kompatibilita současného přihlašovacího toku není zárukou jeho neměnnosti.

Navržené stavy přístupu: nepřihlášeno, potřeba přihlášení, čekání na připravenost Miloše, přihlašování, čekání na MFA, přihlášeno, pokus vypršel, chyba a odpojeno.

Při potřebě přihlášení proxy pozastaví závislé operace a uloží událost pro Iris. Aida nejprve oznámí, proč je přístup potřeba. Spolehlivý výchozí postup je zahájit časově omezenou výzvu až po Milošově „teď“. Přesné chování automatického spuštění po upozornění se může později upravit, nesmí však předpokládat, že doručená událost znamená přečtenou zprávu.

Současně běží pouze jeden přihlašovací pokus. Po zmeškání se bez opakovaných MFA výzev čeká na nový pokyn. Po úspěchu se obnoví čekající práce. Platná relace se používá bez nového přihlášení před každým čtením. MFA otevře relaci, ale nemění oprávnění k operacím.

Aplikace ukazuje stav přístupu, poslední synchronizaci a čekající operace. Umožňuje přihlášení, ruční synchronizaci a odpojení. Provoz při zamčené obrazovce, restartu, uspání a odhlášení uživatele musí být ověřen. Offline proxy neznamená ztrátu fronty práce; Iris může dále připravovat podklady z označených starších dat.

## Bezpečnostní hranice Aidy vůči +4U

**Závazný požadavek Miloše z 18. října 2026:** Aida nikdy přímo nevolá rozhraní +4U a nikdy nedostává přihlašovací údaje, tokeny, cookies nebo autorizační hlavičky. Platí to i pro její delegované úlohy, ostatní +4U pluginy, prohlížeč a přímé síťové nástroje. Instrukce nejsou samy o sobě technickou izolací.

Cílová cesta je **Aida → omezené rozhraní Iris → pracovní jádro Iris → nativní Iris Connect → schválené rozhraní +4U**. U přihlášení může omezené rozhraní předat pevný řídicí požadavek přímo nativnímu konektoru. Aida dostává jen stav, podklady a výsledek schválené operace. Žádný AI agent nedostává bearer; autorizační hlavičku připojuje výhradně nativní konektor uvnitř svého procesu. Ověření transportu mezi službami nesmí vystavovat jeho tajné údaje modelu.

Rozhraní Aidy nesmí obsahovat obecné HTTP volání, URL, hlavičky, předávání příkazů shellu, skriptů, export relace ani přístup k surovým odpovědím přihlášení. Parametry musí mít pevné schéma a odpovědi se skládají z povolených polí; libovolné výjimky a autentizační odpovědi neprocházejí ven. Seznam uuCommandů a jeho schválený hash se tímto požadavkem nerozšiřují.

**Co je v prototypu technicky přítomné:** Keychain omezený podepsané nativní aplikaci, hardened runtime bez debuggerových výjimek, pevná síťová politika nativního konektoru, vzájemné ověření místního klienta, striktní parametry a odpovědi bez vlastního autentizačního tokenu. IrisControl používá pouze místní UNIX socket; přímé síťové volání +4U neobsahuje. IrisRead vrací normalizovaná pracovní data; token zůstává v nativním ReadTransport. Jde o hranice těchto rozhraní, nikoli o důkaz izolace celého Macu nebo platformy Dot.

**Aktuální napojení Aidy:** Miloš potvrdil odebrání obecného přístupu k Macu, přepnutí na Iris Local a následně hlasový rozhovor nad briefingem. Původní plugin Iris Tunel byl po jeho souhlasu odinstalovaný. Omezený MCP proces má ověřený sandbox a Aida má používat výhradně tuto cestu.

**Co ještě není doložené:** úplný audit ostatních nástrojů, pluginů a dřívějších úloh Aidy a vynucení zákazu přímého volání +4U v celém prostředí platformy. Instrukce v chatu, custom rules a absence tokenu v protokolu nenahrazují zákaz přímého síťového přístupu. Místní agent může měnit zdrojový kód; současný ad-hoc podepsaný vývojový build v zapisovatelném projektu není finální oddělená instalační doména.

**Před rozšířením autonomie:** zachovat odebraný obecný přístup Aidy k Macu a omezené MCP; dokončit audit a odebrání ostatních přímých +4U konektorů a cest k přihlášeným relacím; ověřit, zda platforma umí takové odebrání skutečně vynutit. Aidě a jejím úlohám nepovolit obecný shell, prohlížeč ani síť v prostředí s přístupem k Iris Connect. Běžící nativní konektor, schválená politika a instalační proces nesmějí být zapisovatelné agentem; nasazení nového buildu a nové důvěry musí být řízené. Zůstane-li obecný cloudový či místní síťový nástroj, doslovný zákaz jakéhokoli přímého HTTP požadavku na +4U není doložený a nesmí se vydávat za splněný. Musí být odstraněn nebo omezen vynucenou politikou prostředí, nikoli jen instrukcí.

**Ověření hranice:** kontrola skutečně dostupných nástrojů Aidy a jejích úloh, izolace procesu a instalace, negativní test nepovolených operací a parametrů, syntetické canary hodnoty v mock autentizaci a kontrola všech výstupních cest včetně chyb. Síťové blokování ověřovat řízeným testovacím cílem a politikou; test sám nesmí porušit zákaz tím, že Aida skutečně zavolá produkční +4U. Žádné pokusy vyčítat skutečné tajné údaje pro „ověření ochrany“. Obousměrné spojení ani úspěšné MFA nejsou důkazem splnění této bezpečnostní podmínky.

## Pravidla provádění příkazů

Proxy poskytuje významově omezené operace, nikoli obecné volání libovolné URL s uživatelovým tokenem. Každá operace se mapuje na schválené uuCommandy, povolené aplikace a workspaces, validované parametry a podmínky provedení. Čtecí charakter se posuzuje podle skutečné sémantiky příkazu, nikoli názvu nebo HTTP metody.

Registr oprávnění obsahuje účel, cílové příkazy, omezení parametrů, požadované schválení, způsob ověření výsledku, pravidlo opakování a verzi politiky. Agenti nemohou registr sami rozšířit. Neznámé operace se odmítají. Proxy ověřuje identitu spárovaného procesu Iris; vystavení prostého lokálního portu samo o sobě není autentizace. Případné vzdálené napojení preferuje autentizované spojení iniciované z Macu.

| Kandidát do registru | Zamýšlený režim |
| --- | --- |
| Čtení úkolů, kalendáře a relevantních podkladů | Automatické čtení v povoleném rozsahu. |
| Vytvoření pracovního bloku | Automaticky podle časových pravidel. |
| Přesun vlastní přesunutelné rezervace | Automaticky po ověření vlastnictví, účastníků a omezení. |
| Zápis přípravy nebo zápisu ke schůzce | Schválení konkrétního obsahu. |
| Změna stavu úkolu | Zpočátku konkrétní pokyn Miloše; širší automatika je budoucí návrh. |
| Přesun společné schůzky | Pro agenty Iris nepovoleno; koordinuje Adéla. |

Tabulka není schválený seznam uuCommandů. Názvy příkazů a jejich přesné podmínky se před aktivací ověří a schválí. Oprávnění k vytvoření a přesunu vlastních rezervací je produktově dohodnuté, ale jeho konkrétní technická realizace a časové parametry ještě chybějí.

Schválení zápisu se váže na konkrétní verzi návrhu. Změna obsahu nebo cíle je zneplatní. Při nejistém výsledku zápisu služba nejprve provede kontrolní čtení, nikoli slepé opakování. Pokud vzdálený systém neposkytuje atomickou kontrolu konfliktu, použije se co nejbližší kontrola před zápisem a následné ověření; úplnou atomickou rezervaci nelze slibovat bez podpory zdroje.

## Rozhraní Aidy

**První briefing – MCP 0.2.0:** na Milošův požadavek přibývá `iris_get_morning_briefing` bez vstupů. Aida čte jen připravený, omezený a schématem ověřený výstup Iris. Samotné zdrojové čtení a sestavení provádí lokální Iris přes podepsaný IrisRead, nikoli Aida nebo MCP server. Jediný soubor s briefingem je výjimkou sandboxu; zdrojové snapshoty dostupné nejsou. Vrací datum, čas podkladů, stav úplnosti, souběhy a nejvýše tři prioritní podklady s explicitními chybějícími informacemi. Po 30 minutách se podklady označí jako zastaralé. Toto není obecný přístup k pracovnímu disku ani nový přímý +4U klient. Automatické plánování, push, pravidelné ranní obnovení a rozhodovací zápisy tím nevznikají.

**Implementované omezené MCP 0.1.0:** čtyři řídicí nástroje nad nativním IrisControl. Jejich proces nemá síť, obecný přístup k uživatelským souborům ani spouštění jiných programů; jedinou výjimkou je konkrétní místní UNIX socket a podepsaný helper. Vstupy, výstupy i validační chyby SDK jsou omezené. Secure MCP Tunnel má samostatný nativní host s odděleným Keychain záznamem pro provozní OpenAI klíč; model, MCP server ani helper tuto hodnotu nedostávají. Na Macu mini jsou ověřené místní MCP i skutečný soukromý tunel. Miloš potvrdil odebrání obecného přístupu Aidy k Macu a její odpověď po volání soukromého pluginu Iris Tunel. Živý MFA průchod přes Aidu při zamčeném Mini uspěl; následný přímý stav potvrdil platnou relaci a zamčený Mac. Kontrola jiných přímých +4U cest, dřívějších úloh a provozu po restartu zůstává samostatná. [Konkrétní implementace, testy a podmínky přepnutí](../services/iris-mcp/README.md).

**První místní realizace (0.3.0):** Aida použije místní úlohu na Macu připojeném v jejím profilu. Nativně spárovaný podepsaný IrisControl obsluhuje oddělený `auth.sock`, takže stav a zahájení přihlášení fungují i bez platného tokenu. Operace jsou pouze `status`, `prepare`, `noticeSent` a `start`; upozornění není souhlas a start vyžaduje následný přímý lidský pokyn, platné jednorázové upozornění a idempotentní requestID. Místní spojení z Aidiny úlohy a příprava požadavku jsou ověřené; doručení upozornění od Aidy potvrdil Miloš a následně nativně prošel noticeSent. Spuštění loginu a MFA přes Aidu ještě ověřené nejsou. Jde o místní pilot bez push MCP Events, vlastního pluginu a trvalého scheduleru; neaktivní Aidu samotný soubor neprobudí. [Nastavení, protokol a provozní hranice](../integrations/aida/README.md).

Navržené operace: `getMorningBriefing`, `getWorkItem`, `getDecisionBrief`, `recordDecision`, `requestPreparation`, `approveMeetingReschedule`, `getAccessStatus` a `startLogin`. Poslední operace smí pouze zahájit autentizaci, ne vrátit přihlašovací údaje.

Schválení přesunu společné schůzky založí požadavek pro Adélu; neprovede přímý přesun v +4U. Dlouhé operace vracejí identifikátor práce. Aida dostává stručný přehled a vyžádá si detail podle tématu hovoru.

Události pro Aidu: připravený ranní briefing, potřebné rozhodnutí, ohrožený termín, potřeba přihlášení, úspěšné nebo zmeškané přihlášení a podstatná blokace. Běžné nezměněné stavy se neoznamují opakovaně. Po restartu se zachová evidence nedoručených událostí a zabrání duplicitám.

Oficiální dokumentace uvádí podporu MCP Events pro dots, s MCP 2.0 a webhookovým doručováním. Způsob instalace vlastního pluginu v Milošově účtu, dosažitelnost služby, přístup k nástrojům během hlasového hovoru a chování doručení se ověří prototypem. Vlastní scheduler Iris zůstává autoritou pro práci; Aida nemá paralelně vytvářet duplicitní plánování.

## Spolehlivost a kontrola výsledků

- Trvalé stavy pracovních kroků, omezené doby běhu a checkpointy dovolí pokračovat po pádu.
- Opakované načtení stejného zdrojového záznamu nevytváří další úkol ani další zprávu.
- Checkpoint synchronizace se posune až po trvalém uložení odpovídajících dat; zpracování probíhá po malých dávkách.
- Změna stavu a událost k jejímu oznámení se ukládají v jedné databázové transakci. Souborové výstupy mají následnou kontrolu konzistence.
- Dokončený běh modelu není hotový úkol. Dokončení vyžaduje existující výstup a splněné kritérium.
- Výpadek jednoho zdroje nebo agenta nezablokuje nezávislé procesy globálním zámkem.
- Limity souběhu, času a nákladů brání tomu, aby příprava málo důležitých položek vytlačila důležitou práci.
- Provozní chyby mají vlastní přehled; do ranního rozhovoru vstupují jen srozumitelným dopadem na připravenost dne.

## Výchozí stav původní Iris

Zdrojový projekt: `/Users/milosvodrazka/Personal/milos_executive_assistant`.

| Část | Využití nebo potřebná změna |
| --- | --- |
| `vault/` | Zachovat znalosti a zdroje; pracovní seznamy převést na databázovou evidenci a generované pohledy. |
| `.claude/skills/` | Převzít použitelné postupy, odstranit automatické sypání kandidátů do inboxu a oddělit role. |
| `mcp-servers/iris-dwg-mcp/` | Využít znalost čtení a mapování dat; přihlášení přesunout za Iris Connect. |
| `mcp-servers/iris-finman-mcp/` | Zachovat jako doménový adaptér při dodržení jeho čtecího rozsahu. |
| `scripts/lib/job.sh` | Nahradit globální zámek a závislost běhu na Git synchronizaci trvalou frontou. |
| `tools/iris-dashboard/` | Využít pro přehled připravenosti, stavu práce a diagnostiky. |
| Signal a meeting pipeline | Zachovat vstupy a užitečné zpracování; změnit zápisy do agendy a zavést checkpointy. |

Při prohlídce byl v úkolech nalezen výpis jedné stránky o 200 položkách a časové filtrování. Migrace musí doplnit úplné stránkování a průkaznost dokončení; nepřítomnost v omezeném výpisu není důkaz uzavření. Kalendářové čtení pro výpočet volného času musí pokrýt všechny blokující položky. Existující rozhraní nemá ověřené vytváření ani přesun pracovních rezervací.

## Otevřené otázky

1. Základní autentizace s Access Code 1 a 2, lidským MFA a bez registrace nového klienta je ověřená. Zbývají provozní obnovy a řízená aktualizace podepsané instalace.
2. Čtecí sady jsou schválené a pilotované. Nové zapisovací commandy, jejich parametry a podmínky je ještě potřeba ověřit a schválit.
3. Časová pravidla rezervací, pevné osobní bloky a pravidla při nedostatku kapacity.
4. Vlastní Iris Local i hlasový rozhovor jsou uživatelsky potvrzené. Otevřené zůstává první plánované doručení a trvalé převzetí rozhodnutí do Iris.
5. Provozní dostupnost při uspání, odhlášení, restartu a novém souhlasu klíčenky. Nasazení a živý MFA průchod při zamčené obrazovce jsou ověřené; ostatní stavy se od zamčení odlišují a zůstávají k ověření.
6. Identifikace správného Signal kontaktu Adély, spolehlivé doručení a pravidla připomínání.

## Podklady

- Původní `CLAUDE.md`, `specification.md`, provozní skripty, MCP implementace a backlog Iris v uvedeném zdrojovém projektu. Přihlašovací konstanty a tajné údaje se do nové dokumentace ani migrace nepřebírají.
- [Dot a připojené počítače](https://learn.chatgpt.com/docs/dots/computers-and-apps)
- [Dot a paměť](https://learn.chatgpt.com/docs/dots/tasks-and-memory)
- [MCP Events](https://developers.openai.com/plugins/build/mcp-events)
- [uuIdentity autentizační protokoly](https://uuapp.plus4u.net/uu-bookkit-maing01/ad1916b8190d46b1bd3bcde1f02a140a/book/page?code=71067309)
- [Apple Keychain Services](https://developer.apple.com/documentation/security/keychain-services)
