# Ověření čtecího rozhraní Iris Connect

## Aktuální stav

Elementary commandy prošly pilotem i běžnou dávkou v 0.7.6. Převod textu ale ignoroval dokumentovaná vnořená rich-text pole. Opravná 0.7.7 je podepsaná a nasazená po bezpečném ukončení předchozí aplikace; čeká na nové místní souhlasy a živé ověření kontrolní schůzky Meetings AI records tool. Záloha 0.7.6 je zachovaná, schválené politiky i MCP beze změny. Poslední cloudově ověřený briefing pro 19. října je current/partial, 14 karet, dvě připravená rozhodnutí; neprázdné aktuální podklady Elementary ještě nejsou doložené. Podrobné důkazy a historie následují.

## Historie opravy časových hranic 0.6.1

Primární dokumentace dohledaná přes uuKnowledgeBase:

- [uuDwRecord/listMyDiaryRecords](https://uuapp.plus4u.net/uu-bookkit-maing01/07bedd5d4f6b4cb49a4193382a8063e6/book/page?code=99057852): GET, dva nezávislé seznamy aktivních a finálních záznamů, validátory date(), výběr DAO listBlockingByDateRange, módy timeBlock/dayBlock.
- [uuDwrActive DAO](https://uuapp.plus4u.net/uu-bookkit-maing01/07bedd5d4f6b4cb49a4193382a8063e6/book/page?code=97936972): predikát `F < f && T > f || F < t && T > t || F >= f && T <= t`, kde F/T jsou startTime/endTime záznamu a f/t hranice dotazu.

Po místním přihlášení, MFA a párování 0.6.0 potvrzeném Milošem selhal první diagnostický dotaz s ISO timestampy jako `httpFailure`. HTTP status ani tělo nebyly exportované; přesnou serverovou příčinu z tohoto výsledku nelze určit. Kontrolní pilot se stejnou relací a původními datumy uspěl: aktivní 2 183/11 stránek, kalendář 302/2 a finální 343/2. Nejde o obecný výpadek přihlášení nebo čtení. Časový kontrakt tím ověřený není.

Oprava 0.6.1 posílá pouze doložený formát datumů YYYY-MM-DD. Místní interval Europe/Prague obalí UTC dny od zaokrouhleného začátku do zaokrouhleného konce, načte i okraje a přesné polouzavřené filtrování provede nativně. Pro pondělí 19. října je místní interval 18. října 22:00Z až 19. října 22:00Z; čtecí obálka posílá 18.–20. října. Nepovolují se nové commandy ani zápisy.

Kalibrace porovnává výsledek s širším vzorkem, úplným aktivním seznamem, sousedními dny a filtrováním na začátku existující události. Zvlášť porovnává neobalený date-only dotaz s doloženým DAO predikátem nad UTC půlnocemi; bez shody nepovolí běžná kalendářní data. `boundaryFilterMatches` znamená přesný místní filtr nad širším čtením, nikoli odeslání časové hranice serveru. Shody jsou důkazem pro aktuální živý vzorek, nikoli garantovaným serverovým snapshotem nebo všeobecným důkazem nezdokumentované sémantiky. Platí jen do nové relace/restartu.

UI rozsah od/do zahrnuje poslední místní den; vnitřní interval je `[půlnoc prvního dne, půlnoc po posledním dni)`. Dotýkající se události se vyloučí, nulová událost patří jen ke dni svého okamžiku. All-day se neurčuje podle názvu. Prázdný den změny času není živý test hraničních událostí; počet vzorků se vrací zvlášť. Syntetické testy pokrývají 23hodinový i 25hodinový den, datumovou obálku, překryvy a přesné bodové hranice. Prošlo 37 nativních testů. Následující oddíly zaznamenávají živou kalibraci 0.6.1 a úspěšnou navazující 0.6.2.

## Živá kalibrace 0.6.1 a navazující 0.6.2

18. října 2026 v 18:59:55 Europe/Prague proběhla pevná read-only kalibrace po novém místním přihlášení potvrzeném Milošem. Podpis tokenu i čtení identity prošly. Příznak diagnostického tlačítka mfaConfirmedByUser byl false; uživatel potvrdil úspěch předepsaného postupu v chatu. Nezaměňovat tento příznak za automatické ověření MFA.

- paddedWindowMatches, activeCoverageMatches, adjacentWindowsMatch a boundaryFilterMatches: true.
- V širším vzorku sedm dayBlock a čtyři vícedenní položky.
- Podzimní den změny času: 25 hodin, dstChecked=true, dstMatches=true, ale nula událostí; nejde o živý test události přes změnu času.
- legacyDateOnlyMatchesUTCMidnight=false, proto verified=false a běžný kalendář zůstal zablokovaný.

Výsledek vyvrátil předpoklad jediného serverového modelu, nikoli přesnost místního filtru. Verze 0.6.2 proto porovnává čtyři pevné modely: UTC/pražská půlnoc a UTC/pražský celý koncový den. Vrací seznam všech shod, bez předstíraného rozlišení při stejných datech. Úspěch vyžaduje shodu alespoň jednoho modelu i všechny ostatní dosavadní kontroly. Syntetický test prokazuje, že datumová obálka pokrývá požadovaný pražský den pro každý z těchto modelů, včetně obou změn času. Neznámá sémantika zůstane zablokovaná.

I vnitřní datumová obálka musí splnit schválený limit 93 kalendářních dnů; příliš dlouhý výběr se po přičtení okrajů odmítne, nikoli rozšíří. Prošlo 38 nativních testů. Podepsaná 0.6.2 byla nasazená; úspěch navazující živé kalibrace je doložený níže. Nečekaná necommitnutá změna vracející ISO timestampy byla před opravou zachovaná do ignorovaného build/unexpected-read-policy-change.patch; Miloš neví o souběžné práci na projektu.

## Úspěšná živá kalibrace 0.6.2 – 18. října 2026

Miloš potvrdil místní souhlasy, nové přihlášení s MFA a čtecí párování i pět nástrojů v obnoveném katalogu Iris Local. Pevná kalibrace skončila v **19:17:25 Europe/Prague** s `verified=true`.

- paddedWindowMatches=true, activeCoverageMatches=true, adjacentWindowsMatch=true, boundaryFilterMatches=true.
- matchingDateModels=[utcInclusiveDay, pragueInclusiveDay]. Vzorek odpovídá zahrnutí celého koncového dne, ale nerozlišuje UTC a pražskou zónu. Adaptér netvrdí, že tuto nejednoznačnost odstranil; datumová obálka bezpečně pokrývá oba modely a přesný místní filtr určuje veřejný interval.
- Sedm dayBlock a čtyři vícedenní položky v širším vzorku.
- dstChecked=true, dstDayHours=25, dstMatches=true, dstRecords=0. Délka dne je správně; živá událost přes přechod času tím ověřená není.
- legacyDateOnlyMatchesUTCMidnight=false zůstává poctivě uvedené pozorování, nikoli chyba ignorovaná pro úspěch. Úspěch vychází z ověřených modelů celého koncového dne a ostatních povinných srovnání.

Běžné calendar.list se tím povolilo pro tuto relaci. Následný skutečný compiler přes podepsaný IrisRead načetl cílový kalendář pro 19. října a vytvořil briefing s calendarCoverage=verified, 11 bloky, třemi prioritami a dvěma souběhy. Skutečný sandboxovaný MCP nástroj vrátil stejná metadata s freshness=current. Nejstarší použitý zdroj byl načten 18. října v 19:17:13 Europe/Prague. Toto je večerní příprava na pondělí; ráno je nutné obnovit podklady, jinak se výstup po 30 minutách označí stale.

Platnost kalibrace končí novou relací či restartem. Konzistence zůstává bestEffort, ne serverový snapshot. Finální záznamy a jejich význam pro dokončení zůstávají contractPending. Úplné podklady zdrojových dokumentů nejsou načtené. Skutečné přednesení Aidou se eviduje samostatně; obnovený katalog ani místní smoke ho nedokládají.

## Aktuální místní ověření – Connect 0.5.0

18. října 2026 v 18:28 Europe/Prague po úspěšném přihlášení přes Aidu a Iris Local Miloš potvrdil nalezení vlastního prostoru, čtecí párování a úspěch nového nativního pilotu. Validovaný sanitizovaný záznam i přímé `IrisRead status` shodně potvrdily ok=true, paired=true a loginRequired=false. Čas aktualizace záznamu byl 18:28:13 Europe/Prague; nejde o opětovné použití starého výsledku.

Výsledky nového pilotu: tasks.listActive načetl 2 183 DW záznamů přes 11 stránek, readSucceeded=true, complete=true, contractVerified=true. Calendar.list načetl 302 záznamů přes dvě stránky a tasks.listFinal 343 záznamů přes dvě stránky; u obou zůstává contractPending, complete=false a contractVerified=false. Číslo 2 183 není počet klasifikovaných pracovních úkolů, protože aktivní DW zahrnují i rezervace a pozvánky. Žádný inbox se tím nevytvořil a pracovní data nebyla vypsaná do konverzace.

Iris Local současně potvrdil platnou relaci, authenticated, busy=false a workPending=false; host je ready, failure=none. Původní Iris Tunel byl na výslovný pokyn odinstalován z účtu. Čtyři MCP nástroje dál slouží pouze řízení přihlášení, nikoli předávání agendy Aidě. Níže uvedené historické stavy před implementací Aidy se nevztahují na tuto aktuální zkoušku. Časové kontrakty diáře a finálních záznamů zůstávají k doložení před provozním plánováním a vyhodnocováním dokončení.

Rozsah `iris-connect-read-v1` schválil uživatel 18. října 2026. Platí pouze na tomto Macu a pro vlastní agendu. Schválené bajty politiky mají SHA256 `6cf1ff32ab677fb78d5a7e840eb324b21bb237027e9a914f2bbb75bc4f6ef0db`; [souhlas](../policies/iris-connect-read-v1.approval.json) je uložen odděleně od původního návrhu.

## Implementované chování

- Nativní aplikace odvodí vlastní identitu až po ověření podpisu a claims tokenu. Z přesného `people/findPerson` přijme jen jeden výsledek se shodnou `uuIdentity` a platným `mtDwBaseUri`. Žádné alternativní commandy, adresy nebo aliasy nezkouší.
- Člověk potvrdí vlastní prostor a přibaleného klienta v nativním okně. Párování a vazba jsou pro tento běh aplikace; zamčení, nové přihlášení a expirace je zruší. Obnova relace po restartu zatím není implementovaná.
- `IrisRead` používá Unix socket s právy 0600 v soukromém adresáři. Obě strany ověří skutečný proces přes audit token socketu a přesný hash podepsaného protějšku. Hardened runtime a nepřítomnost debugger entitlementů jsou povinné. Klient nečte klíčenku.
- Proxy sestavuje jen schválené GET požadavky. Parametry objektů se posílají jako JSON v query hodnotách; server musí potvrdit index a velikost stránky. Nepodporované parametry nebo jiné serverové warnings se odmítají.
- Aktivní úkoly se načítají bez časového filtru. Diář má dvě samostatné stránkovací metadata; adaptér kontroluje obě. Změna počtu, duplicity a neúplná stránka ukončí operaci jako neúplnou.
- Síťová vrstva nevstupuje na redirecty, omezuje průběžně velikost odpovědi, časy, počet pokusů, souběh i frekvenci. 401 a 403 nevyvolají opakování přihlášení ani rozšíření oprávnění.
- `diagnostics.verifyReads` vrací jen pevné kontroly a počty. U neověřených časových kontraktů je `complete=false` a `contractPending`; běžný klient jejich pracovní data nedostane. Úspěšné čtení není tvrzením o všech kalendářních okrajových případech.

## Živý pilot

Automatické ověření: 17 testů prošlo (5 přihlašovacího protokolu, 8 politiky a stránkování, 4 nativního HTTP adaptéru). Používají syntetické údaje a HTTP odpovědi, nikoli skutečné přihlašovací údaje. Dočasný RSA klíč vyžadoval systémovou kryptografickou službu mimo vývojový sandbox. Zůstává známé upozornění SDK na file-based Keychain ACL z přihlašovacího prototypu.

Živý pilot buildu 0.2.0 proběhl úspěšně 18. října 2026. Uživatel dokončil nové AC1/AC2 přihlášení, potvrdil MFA, vlastní prostor i místního klienta a potvrdil v konverzaci načtení úkolů a kalendáře. Agent četl pouze sanitizovaný stav; kódy ani token nedostal.

| Operace | Skutečný výsledek | Provozní význam |
| --- | --- | --- |
| `people/findPerson` | Jednoznačná shoda vlastní identity a platný `mtDwBaseUri`, potvrzené místní párování. | Vlastní vazba funguje; žádná alternativa nebo fallback nebyly použity. |
| `calendar.list` | 302 záznamů, 2 stránky; výchozí okno 11. 10. až 17. 11. 2026. | Čtení i obě stránkovací části fungují. Časové hranice/overlap zůstávají `contractPending`, `complete=false`. |
| `tasks.listActive` | 2 183 záznamů, 11 stránek, bez časového filtru, všechny identifikátory unikátní. | Normální klient obdržel normalizované výsledky s `complete=true`, konzistence `bestEffort`. |
| `tasks.listFinal` | 343 záznamů, 2 stránky; výchozí okno 19. 9. až 18. 10. 2026. | GET a formát stránkování fungují. Význam datového filtru a stavů zůstává `contractPending`, `complete=false`. |

Celý diagnostický pilot byl zopakován přes skutečné podepsané IPC se stejnými počty. Samostatný Python proces stejného uživatele byl odmítnut jako `pairingRequired` ještě před zpracováním požadavku. Provozní `calendar.list` a `tasks.listFinal` vrátily jen `contractPending`, žádné záznamy. Ověřil se tedy i zákaz vydávání neověřených výsledků za běžnou agendu.

Z 2 183 aktivních DW záznamů má 1 008 typ `reserveTime` (pozvánka nebo rezervace). Tento počet nelze prezentovat jako počet pracovních úkolů. Jádro Iris musí provést klasifikaci před zařazením do agendy; samotné čtení žádný inbox nevytváří. Ve výpisu nebyl záznam bez `endTime`; chování bez termínu je otestované synteticky, nikoli tímto živým vzorkem.

Při opakování se v aplikaci provede přihlášení, nalezení a potvrzení vlastního prostoru a čtecí pilot. Agent nečte přihlašovací UI, Keychain ani surové HTTP odpovědi. Pro kontrolu použije jen:

```sh
python3 tools/iris-connect-read-status.py
"build/Iris Connect.app/Contents/MacOS/IrisRead" status
"build/Iris Connect.app/Contents/MacOS/IrisRead" diagnostics.verifyReads
```

Normální čtení má tvar `IrisRead tasks.listActive`, případně `IrisRead calendar.list 2026-10-18 2026-10-25`. Operace s nedoloženým kontraktem vrátí `contractPending` místo záznamů. Periodický job, Aida, pracovní zápisy a přenos na Mac mini nejsou součástí tohoto kroku.

## Zbývající podmínky

U diáře doložit inkluzivitu hranic, interpretaci dat vůči místní časové zóně a události překrývající okno včetně celodenních a osobních bloků. U finálních záznamů navíc doložit význam časového filtru a vlastní elementární stavy. Ověřit skutečné počty a stránkování cílové verze serveru. Do té doby nemohou tyto výsledky potvrdit volný čas ani dokončení úkolu.

Při pilotu 0.2.0 uživatel musel ručně zvolit **Přihlásit pomocí Plus4U Access**. Verze 0.2.1 přidává bezpečně omezenou jednorázovou volbu uvnitř nativní aplikace; [záznam přihlášení](iris-connect-verification.md) eviduje její samostatné ověření. Nástroje agenta přihlašovací UI ovládat nesmějí. Zahájení přihlášení přes Aidu a její upozornění před MFA zatím implementované nejsou.

Samostatná služba `iris-core` dosud neexistuje; přibalený `IrisRead` je první místní klient pro ověření rozhraní. Aida se k němu nepřipojuje přímo. Přibalený JSON není obecný konfigurovatelný vykonávač commandů a změna jeho obsahu operace nerozšíří.

## Doručovací cesta po prvním neúspěchu Aidy

Aida v 19:19 hlásila invalidRequest. Nativní kalendář a místní briefing fungovaly; cloudový test chybu zopakoval. Diagnostika pouze metadat procesů odhalila tři staré osiřelé tunely/MCP procesy. Po odstranění a čistém spojení skutečný cloudový iris_get_morning_briefing uspěl. Opravený host 0.2.1 prošel syntetickými životnostními testy i živým restartem bez přeživších potomků. Následný cloudový stav i briefing uspěly s datem 19. října, verified a počty 11/3/2; první volání po restartu mělo přechodný timeout. Problém doručovací cesty se neřešil změnou kalendářního kontraktu ani novým MFA. Miloš následně potvrdil: Aida vypsala stručný ranní briefing. Textové předání po opravě je tedy uživatelsky potvrzené. Celé znění její odpovědi ani přesný čas opakovaného volání nebyly dodané; konkrétní obsah je technicky doložen přímým cloudovým testem, nikoli rozborem této uživatelské odpovědi. Hlasový průchod zůstává neověřený.


## Rozšíření zdrojů pro briefing 0.7.0

18. října Miloš schválil čtecí sadu `iris-connect-briefing-sources-v1` s výslovným doplněním `keyTask` a `request`. Schválení váže původní posouzený hash i výsledný hash po těchto dvou doplněních. Zdrojový výběr je omezený na čerstvou vlastní agendu a jeden krok dokumentových odkazů. Žádná změna +4U dat, příloha nebo nový přístup Aidy tím nevzniká.

Nativní implementace obsahuje validaci cíle, svázání entity a stránky, limity celé dávky včetně opakování, místní textové limity, označení nepodporovaného nebo neúplného obsahu a stav ověření po jednotlivých typech. Pevný `diagnostics.sources` nesmí vracet texty; `sources.prepare` připustí normalizované podklady jen ověřeného typu. Chybějící typ bez vlastní položky se neověřuje náhradním cizím zdrojem. Ověření platí pouze pro aktuální relaci.

Místní souhlas s obnovou čtecího párování váže přesné podpisy aplikace i IrisRead, hash identity a potvrzený prostor. Po novém loginu nativní aplikace znovu ověří vlastní profil; souhlas neobnovuje token nebo MFA pokyn. Nový build vyžaduje nové místní povolení.

Živé čtení tohoto rozšíření zatím neproběhlo. Ani syntetické testy, schválená politika a podepsané sestavení nejsou důkazem živého čtení těchto zdrojů. Trvalá fronta, naplánované běhy 18:00/7:00, obsahová analýza nových podkladů a pravidelné předání Aidou jsou stále navazující práce podle `docs/briefing-automation.md`.


Podepsaná 0.7.0 je nyní nasazená na tomto Macu. Závěrečná sada: 45 testů ConnectCore a 10 nativního čtení, všechny úspěšné; čtyři testy správce spuštění také prošly. Testy používají výhradně syntetická data. Kontrola prostředků nainstalovaného bundlu potvrdila schválený hash, původní DW politika zůstává beze změny. Při výměně byl dvakrát ověřen nečinný login; předchozí bundle je zachovaný v ignorovaném build/backups. MCP host nebyl zastavený a sanitizovaný stav dál potvrzuje ready. Relace ani MFA se při nasazení nespustily. Čeká se na místní souhlasy člověka, jeho přihlášení a čtecí párování před živým pilotem.


## Aktuální živé ověření 0.7.1 a automatické přípravy

Následující stav nahrazuje čekání uvedené u historické 0.7.0 výše. Miloš dokončil nový místní souhlas, ověření přihlášení/MFA a párování. Fronta po skutečném dokončení sama navázala. Pilot ověřil ManagementKit meeting/document/keyTask/request s počty stran 1/1/4/1. Elementary meeting zůstal schemaMismatch, bez textového výstupu a bez prokázané přesné příčiny; neznámé warnings se dál odmítají. Změna na 0.7.1 neopravila tento živý kontrakt. Nativní sada má 46 Core + 11 Native úspěšných syntetických testů.

Pro pondělí 19. října vznikl nový soukromý balíček: aktuální agenda od 20:23:56 Europe/Prague, zdroje do 20:26:25; devět podkladů na 19 stránkách. Model připravil dvě rozhodovací analýzy s pěti doslovně ověřenými citacemi. Pevný publisher zkontroloval balíček a soukromý pracovní stav, předal 14 karet, uvedl neúplnost a stav partial. Místní sandboxované stdio i skutečný cloudový Iris Local vrátily nový výstup jako current, calendarCoverage=verified, 11 bloků / 3 priority / 2 souběhy. Tento test nevyvolal žádné přihlášení ani MFA.

Aktivní rozvrhy, stavy a rozdíl mezi uloženou rutinou a skutečným doručením eviduje [runbook](briefing-runbook.md). Uživatel předal potvrzení uložené rutiny hlavní Aidy, ale první plánované ranní doručení a hlas ještě neproběhly. Podklady zůstávají částečné; nelze tvrdit kompletní přípravu všech schůzek.


## Oprava Elementary – diagnostika a 0.7.4

Po místním potvrzení 0.7.2 prošla kalibrace kalendáře a přesná pevná diagnostika určila elementaryPageRequest/serverWarnings. Detail a identifikátory prošly, nešlo o přihlášení nebo renderování stránky. Miloš následně výslovně schválil jednorázový výstup koncového technického názvu podle přesného hashe výjimky. V 0.7.3 byl jediným vráceným názvem unsupportedKeys; nevracely se zprávy, hodnoty, obsah nebo autentizační údaje.

Zdrojový export názvů a přibalení diagnostického povolení jsou odstraněné. Ověřený hardened bundle 0.7.4 neobsahuje diagnostické prostředky; při nasazení byly oba dočasné bundly 0.7.3 s exportem odstraněné. Záloha 0.7.2 zůstává. Výjimka je vyčerpaná, nepovoluje nové zjišťování názvů.

Oprava rozpozná přesnou strukturu standardního unsupportedKeys i bez namespace. Jen pilot smí jedním kalibračním krokem odstranit explicitně odmítnuté schválené aliasy a ověřit užší požadavek stejného commandu. Každá vazba schůzka/stránka/BID musí zůstat; neznámý klíč nebo další varování vše odmítne. Běžné čtení nic nekalibruje a používá jen ověřený profil stejné identity a expirace relace. Testy ověřily rozsah, vazby, nezpřístupnění libovolných názvů, druhé varování, nepřenesení profilu do nové relace a stejné čtení bez vykonávání komponent. Prošlo 46 Core + 17 Native testů.

Nasazení proběhlo po dvou kontrolách busy=false a ověření ukončení Connect, bez restartu MCP nebo automatického MFA. Živý pilot a nový briefing čekají na místní souhlasy člověka pro podpis 0.7.4. Syntetický úspěch sám není živým důkazem opravy.


## Navazující kontrola a 0.7.5

Po uživatelském dokončení přihlášení 0.7.4 pilot kalendáře prošel, ale Elementary dál skončil na elementaryPageRequest/serverWarnings se čtveřicí true/true/false/true a bez známých odmítnutých parametrů. Všechny čtyři ManagementKit typy prošly s počty stran 1/1/4/1. Živá oprava v této verzi tedy prokázaná není.

0.7.5 přidává přísné rozpoznání kompaktní struktury a prázdných unsupportedKeys metadat, případně důkaz identity vrácené hlavní stránky, pokud server odmítl všechny explicitní aliasy stránky. Neignoruje neznámá varování. Pevné počty tvarů neobsahují zprávy, hodnoty ani libovolné názvy. Prošlo 46 Core + 20 Native testů; všechny použily syntetická data. Bundle prošel ověřením podpisu a obou schválených hashů. Před výměnou bylo ověřeno busy=false a správce ukončil starý proces; MCP host zůstal běžet. Nový proces běží, ale živé čtení a briefing zatím čekají na nový místní souhlas člověka.


## Živý pilot 0.7.5 a dokumentovaný unsupportedKeyList

Po uživatelském obnovení souhlasů, přihlášení a MFA prošel kalendář. Elementary zůstal odmítnutý v elementaryPageRequest/serverWarnings: parameterNames=[], shape=[true,true,false,true], warningShape=[1,1,0,0,0,1,1,0,0,0,0,0]. Pevné počty dokazují objekt varování s objektem paramMap, nikoli použití kompaktního seznamu či prázdných metadat. ManagementKit znovu prošel na 1/1/4/1 stranách.

Následná kontrola lokální dokumentace uuAppServer Errors and warnings nalezla dokumentovaný tvar paramMap.unsupportedKeyList (seznam cest $.…); parser dosud rozpoznával především unsupportedKeyMap. 0.7.6 přidává právě tento seznam do stejné přísné validace známých aliasů, severity a vazeb. Jeho skutečný výskyt a výsledný užší GET zatím musí doložit živý pilot. Nepřibylo žádné pole diagnostiky, výstup hodnot ani povolený command. Syntetické testy s dokumentovaným tvarem i odmítnutím neznámých parametrů, error severity a odstranění obou identifikátorů schůzky prošly (46 Core + 20 Native).


Podepsaná 0.7.6 byla po ověření obou schválených hashů, nepřítomnosti dočasného diagnostického prostředku a busy=false nasazená přes správce služeb. Předchozí 0.7.5 je zachovaná jako záloha; MCP host nebyl restartovaný. Nový proces běží, čeká na místní souhlasy a lidské přihlášení. V tomto bodě se nový briefing nepublikoval a čtení Elementary nebylo prohlášené za ověřené. Samostatně prošlo všech 11 testů pracovního jádra včetně obnovení již publikované úlohy bez vytvoření nové a bez automatického MFA.


## Úspěšný živý pilot 0.7.6

Po místním obnovení souhlasů a lidském přihlášení/MFA prošla kontrola kalendářních hranic. Elementary pilot následně úspěšně načetl jednu hlavní stránku; parameterNames=[oid,bid] dokládá zúžení právě o tyto dva explicitně odmítnuté aliasy. Zachované meetingId/id i uuEccPage.oid/uuEccPage.bid mají stejné nativně získané hodnoty. Příčinou byl dokumentovaný seznam paramMap.unsupportedKeyList, který původní parser neznal, a nadbytečné aliasy oid/bid. Nešlo o renderování stránky, neplatné přihlášení nebo potřebu jiného commandu.

ManagementKit meeting/document/keyTask/request současně prošly na 1/1/4/1 stranách. Pilot nevrátil žádné materiály ani autentizační údaje. Kontroly byly soukromě uložené k nezměněné aktuální relaci; neprováděl se login ani MFA nástroji agenta. To je živý důkaz kontraktu prvního vybraného vlastního Elementary meeting, nikoli úplnosti obsahu všech schůzek. Následuje běžné sources.prepare se stejným ověřeným profilem a obsahová příprava pondělního briefingu.


## Běžná dávka 0.7.6 a převod textu

Běžné sources.prepare se stejným ověřeným profilem úspěšně načetlo 24 materiálů / 34 stran, z toho 15 Elementary meeting stránek. U těchto 15 byl výstup přípravy a zápisu téměř prázdný (14 bez textu, jedna příprava jen dva znaky). To není důkaz, že server obsahuje prázdné podklady. Miloš uvedl kontrolní schůzku „Meetings AI record tools“, v kalendáři „Meetings AI records tool“, kde podklady očekává.

Porovnání s původní technickou čtečkou a lokální znalostní dokumentací Uu5RichTextBricks.Block prokázalo podporovaný typ uu5String = string | [string | object]. Dosavadní nativní převod četl tuto vlastnost jen jako string, takže pole ignoroval. Zdrojová 0.7.7 doplňuje omezenou rekurzi pouze dokumentovaných uu5String/uu5string polí známých RichText.Block tagů, bez renderování, s limity 1000 uzlů, hloubkou 20 a 16000 znaky. Neznámý tvar se označuje jako neúplný. Spojený text se znovu kontroluje; při citlivém dítěti se zadrží celý blok, aby nezůstaly sousední fragmenty. Prošlo 47 Core + 21 Native testů včetně skutečného typu pole a oddělení přípravy/zápisu. Živý důkaz neprázdného aktuálního textu zatím chybí.

Před novým nativním buildem byl z čerstvé dávky publikovaný pondělní briefing se dvěma znovu posouzenými rozhodovacími analýzami a ověřenými citacemi. Skutečný cloudový Iris Local vrátil current, 19. října, verified, 11 bloků, 14 karet, 2 prepared a partial. Čas zdrojů agendy 21:24:58 Europe/Prague, načítání podkladů skončilo 21:28:20. Prázdné výňatky Elementary nejsou označené za obsahově připravené.
