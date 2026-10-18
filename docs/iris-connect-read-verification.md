# Ověření čtecího rozhraní Iris Connect

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

Aida v 19:19 hlásila invalidRequest. Nativní kalendář a místní briefing fungovaly; cloudový test chybu zopakoval. Diagnostika pouze metadat procesů odhalila tři staré osiřelé tunely/MCP procesy. Po odstranění a čistém spojení skutečný cloudový iris_get_morning_briefing uspěl. Opravený host 0.2.1 prošel syntetickými životnostními testy i živým restartem bez přeživších potomků. Následný cloudový stav i briefing uspěly s datem 19. října, verified a počty 11/3/2; první volání po restartu mělo přechodný timeout. Problém doručovací cesty se neřešil změnou kalendářního kontraktu ani novým MFA. Skutečné předání Aidou po opravě zatím čeká na potvrzení.
