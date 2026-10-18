# Návrh čtecího rozhraní Iris Connect

**Schváleno uživatelem, verze 1, 18. října 2026.** Iris smí přes nativní aplikaci číst vlastní pracovní agendu přihlášeného Miloše na tomto Macu. Cílem je včas zachytit úkoly, připravovat řešení a znát skutečně obsazený čas. [Záznam schválení](../policies/iris-connect-read-v1.approval.json) váže souhlas na přesný hash původního návrhu; podmínky provozní aktivace nadále platí.

Strojově čitelný protějšek je [původní návrh politiky](../policies/iris-connect-read-v1.draft.json). Jeho bajty včetně tehdejšího stavu návrhu zůstávají beze změny. Nový build přibaluje tento soubor a ověřuje jeho schválený hash; rozsah vynucuje nativní kód. Schválení umožňuje implementaci a omezené živé ověření uvedených čtení. Běžná synchronizace začne až po splnění podmínek níže. Změna rozsahu, cíle nebo commandů vyžaduje nové schválení.

## Sada commandů

Všechny čtyři pracovní operace používají **GET**. Agent neposílá URL, HTTP hlavičky, token, identitu ani surové DTO. Parametry uuCommandu sestavuje Iris Connect podle pevného adaptéru.

| Operace proxy | Přesný uuCommand | Povolené parametry sestavené proxy | Rozsah a podmínka |
| --- | --- | --- | --- |
| Interní nalezení vlastního prostoru | `people/findPerson` | Pouze `uuIdentity` odvozené z ověřené přihlášené identity. | Pevná aplikace uuPlus4UPeople uvedená níže. Žádné hledání podle jména nebo e-mailu. Výsledek musí jednoznačně odpovídat vlastní identitě. |
| `calendar.list` | `uuDwRecord/listMyDiaryRecords` | `dateFrom`, `dateTo`, `pageInfo.pageIndex`, `pageInfo.pageSize`. | Pouze vlastní připnutý Digital Workspace. Všechny blokující záznamy včetně osobních rezervací a celodenních bloků. |
| `tasks.listActive` | `uuDwRecord/listActiveRecords` | `pageInfo.pageIndex`, `pageInfo.pageSize`, pevné `sorterList=[{key:"startTime",ascending:false}]`, pokud jej potvrzuje cílový kontrakt. | Vlastní aktivní záznamy **bez časového filtru**, včetně starých nesplněných a bez termínu. Žádné další filtry omezující úplnost. |
| `tasks.listFinal` | `uuDwRecord/listFinalRecords` | Kandidátní DTO: `dateFrom`, `dateTo`, `pageInfo.pageIndex`, `pageInfo.pageSize`. | Vlastní finální záznamy pro kontrolu dokončení a změn. **Podmíněná položka:** před provozem ověřit přesný kontrakt; nedokumentované parametry nevymýšlet. |

Pevná People base URI:

```text
https://uuapp.plus4u.net/uu-plus4upeople-maing01/56ac93ddb0034de8b8e4f4b829ff7d0f
```

Adresu vlastního prostoru získá pouze nativní aplikace z `mtDwBaseUri`. Ověří HTTPS, host `uuapp.plus4u.net`, metamodel `uu-myterritory-dwg01`, nepřítomnost userinfo, portu, query a fragmentu a platný tvar workspace identifikátoru podle kontraktu. Konkrétní base URI se připne v místním nastavení po potvrzení vazby v nativním okně. Politika nepovoluje libovolné AWID na tomto hostu. Agent dostane jen neprůhledný identifikátor vazby.

Pokud chybí ověřitelné přiřazení identity, odpověď je nejednoznačná nebo URI nevyhovuje, aplikace čtení zastaví. Nepřebírá staré hledání „libovolný řetězec obsahující dwg01“. Změna účtu nebo prostoru zruší vazbu a oddělí cache; nový prostor se nepotvrdí automaticky. Změna hostu či metamodelu vyžaduje novou politiku.

## Čas a úplnost dat

- **Kalendář:** výchozí interval od 7 dní před dneškem do 30 dní po dnešku, nejvýše 93 kalendářních dní v jednom požadavku. Agent může zvolit jiný interval uvnitř limitu. Časová zóna `Europe/Prague`; lokální den a přechody letního času se převádějí v adaptéru. Přesnou inkluzivitu hranic a překryv dlouhých událostí je nutné ověřit před aktivací. Rezervace přesahující okno nesmějí zmizet.
- **Aktivní úkoly:** bez `dateFrom` a `dateTo`. Stáří ani chybějící termín nejsou důvod k vyřazení. Proxy vrací vlastní aktivní DW záznamy s klasifikací; jádro odlišuje úkol, pozvánku a rezervaci. Není to záruka načtení všech aktivit ze všech Business Territories, pokud nejsou ve vlastním DW.
- **Finální záznamy:** výchozí posledních 30 dní, nejvýše 93 dní na požadavek. Je nutné ověřit, vůči kterému datu server filtruje; nelze předpokládat datum dokončení. Pro starší úkol může stav zůstat neznámý. Pokud kontrakt časové omezení nepodporuje, tento command zůstane zablokovaný do úpravy návrhu.
- **Stránkování:** proxy řídí stránky od indexu 0, velikost 200; agent stránkování neovládá. Na jednu operaci nejvýše 50 stránek a 10 000 záznamů. Ukončení výpisu vychází z ověřeného kontraktu `pageInfo`, nikoli z předpokladu, že jedna stránka stačí.
- Každý výsledek obsahuje `fetchedAt`, `scope`, interval, `complete`, `consistency`, počty a případný pevný důvod neúplnosti. Bez serverového snapshotu se konzistence označí `bestEffort`, nikoli atomický obraz. Změny počtu, duplicitní nebo chybějící identifikátory a nestabilní stránky se označí jako neúplné a vyžádají nové načtení.
- **Absence není dokončení.** Úkol se nikdy neuzavře jen proto, že vypadl ze stránky, okna nebo aktivního seznamu. Rozhoduje doložený vlastní stav elementární aktivity ke stejnému stabilnímu zdrojovému identifikátoru. Neznámé stavy zůstanou neznámé; finální záznam může být také zrušený.
- Neúplný nebo zastaralý kalendář neposkytuje potvrzenou dostupnost. Chybějící účastníci nejsou důkazem, že rezervace patří pouze Milošovi a lze ji přesunout.

## Rozhraní pro Iris

Agentům se zpřístupní pouze `calendar.list({dateFrom?,dateTo?,fresh?})`, `tasks.listActive({fresh?})`, `tasks.listFinal({dateFrom?,dateTo?,fresh?})` a obecný stav připojení. Data se vracejí jako normalizované JSON; `profile.resolveOwnWorkspace` zůstává interní operací aplikace. Neznámé parametry se odmítají.

Výstup obsahuje identifikátory zdrojových záznamů, název, textový popis, termín nebo začátek a konec, celodennost, dostupné stavy a vlastní elementární aktivitu, prioritu, druh záznamu a zdrojový odkaz. Účastníci, zadavatel a místo jen pokud jsou součástí daného vlastního záznamu; žádné další dohledávání osob. Neznámá klasifikace je explicitní. Záznamy osobního volna se zahrnou do obsazenosti.

Přenášejí se jen pole potřebná pro agendu, nejvýše 32 KiB textu na popis. Zkrácení má příznak `contentTruncated`; zdrojový text se nikdy nevykonává jako HTML, skript nebo instrukce měnící oprávnění. Odkazy jsou data, proxy je automaticky nenásleduje. Surová odpověď, token, cookies, autentizační hlavičky a interní údaje přihlášení se agentovi neposkytují.

Přístup má jen místně spárovaná služba Iris na tomto Macu. Cílová realizace je lokální IPC s ověřením procesu protistrany a potvrzením párování v nativní aplikaci; samotný soubor socketu s právy 0600 nestačí jako ověření identity procesu. Žádné síťové naslouchání, vzdálený přístup nebo obecný HTTP tunel. Rozhraní Aidy později zprostředkuje Iris; Aida nedostane přímý autentizovaný přístup k +4U.

## Provozní omezení

| Omezení | Návrh hodnoty |
| --- | --- |
| Souběžné vzdálené požadavky | Nejvýše 2, shodné požadavky sdílejí jeden běh. |
| Frekvence vůči pracovním endpointům | Nejvýše 30 pokusů za minutu, krátký burst 4; zahrnuje opakování a interní nalezení prostoru. |
| Timeout | 20 s na HTTP pokus, 180 s na jednu operaci včetně stránek a čekání. |
| Odpověď | Nejvýše 4 MiB po dekompresi na stránku, 50 MiB za operaci. Překročení se vrací jako neúplnost, nikoli úspěšný prázdný seznam. |
| Opakování | Nejvýše 2 po prvním pokusu, jen síťové chyby, 429, 502, 503, 504; backoff a `Retry-After` v rámci časového limitu. Žádné opakování přihlášení při 401/403. |
| Cache | Kalendář 60 s, úkoly 120 s. `fresh=true` cache obejde, stále platí společné limity. Starší data jen s explicitním `stale=true`; nesmějí být vydávána za aktuální. |
| Plánování čtení | Tato politika neaktivuje periodický job; synchronizace se nejprve ověří na vyžádání. |

Cache a pracovní data zůstanou v místním úložišti Iris s právy pro uživatele, mimo Git a diagnostické logy. Nativní aplikace drží pouze omezenou cache posledních výsledků; její expirace není pokyn ke smazání historie úkolu v jádru Iris. Logy mají jen ID operace, čas, počty, dobu a pevný stav chyby, bez názvů, popisů, surových odpovědí a URL s parametry.

Chybějící nebo expirovaná relace vrátí `loginRequired`. Nevyvolá lavinu MFA pokusů. Uživatel má být nejprve upozorněn Aidou a přihlášení lze znovu spustit na jeho pokyn; toto propojení je samostatný dosud neimplementovaný krok. Během prvního pilotu přihlášení zahajuje uživatel v nativní aplikaci.

## Co tato verze nepovoluje

- Žádné vytvoření, úpravy, označení jako přečtené či vyřízené, přesuny nebo mazání pracovních záznamů. Rezervace času bude samostatná schválená sada.
- Žádné cizí diářové nebo personální vyhledávání. Kontakty již přítomné u vlastní schůzky lze vrátit jako její součást.
- Žádný fallback na `uuDwRecord/listDiaryRecords`, starý alias `/findPerson`, jiný host nebo command po chybě 403/404.
- Žádné `meeting/load`, `meeting/page/load`, dokumenty, přílohy ani načítání libovolné zdrojové URL. Podrobné přípravy mohou později potřebovat samostatně schválené čtení obsahu schůzek.
- Žádný export přihlašovacích údajů nebo tokenů, obecný vykonávač commandů, vzdálené rozhraní nebo migraci na Mac mini.

Již ověřené pevné autentizační operace Iris Connect zůstávají oddělené od této pracovní sady; například POST při výměně autorizačního kódu není povolením pracovních zápisů.

## Podklady a podmínky aktivace

Podklady z uuKnowledgeBase rozlišují aktuální dokumentaci a původní adaptér. Žádný z těchto čtyř pracovních commandů nebyl v nové Iris Connect zatím živě ověřen.

| Command | Podklad a zbývající ověření |
| --- | --- |
| `people/findPerson` | [Aplikační model](https://uuapp.plus4u.net/uu-bookkit-maing01/75b4e8cb904a434f846857df4bc2e438/book/page?code=85266728), [business model](https://uuapp.plus4u.net/uu-bookkit-maing01/75d4d6d474064fb7ab89f821f95c56f5/book/page?code=61664747). Ověřit přesnou obálku odpovědi, shodu identity a `mtDwBaseUri`. Původní Iris používá zastaralý alias a jiná kandidátní pole; ta se nepřebírají. |
| `uuDwRecord/listMyDiaryRecords` | [Specifikace](https://uuapp.plus4u.net/uu-bookkit-maing01/07bedd5d4f6b4cb49a4193382a8063e6/book/page?code=99057852) a původní adaptér. Dokumentace uvádí datumy a `pageInfo`, starý adaptér čte `uuDwrActiveList` a `uuDwrFinalList`. Ověřit obálky, stránkování, osobní/celodenní bloky a časové hranice. |
| `uuDwRecord/listActiveRecords` | [Specifikace](https://uuapp.plus4u.net/uu-bookkit-maing01/7c19861dc05c443d9d20acc467cf59f3/book/page?code=94382644), [další popis](https://uuapp.plus4u.net/uu-bookkit-maing01/07bedd5d4f6b4cb49a4193382a8063e6/book/page?code=90349292). Popsané `uuDwRecordList`, `pageInfo` a `sorterList`. Ověřit serializaci parametrů, řazení a zahrnutí záznamů bez termínu. |
| `uuDwRecord/listFinalRecords` | Jen zdroj `mcp-servers/iris-dwg-mcp/src/dwg-service.js` v původní Iris. Přesnou aktuální specifikaci se nepodařilo doložit. Ověřit metodu, DTO, stránkování, význam datového filtru a stavy; do té doby zůstává mimo běžný provoz. |

Po schválení se postupuje takto:

1. Implementovat vynucování politiky v nativní aplikaci a párování služby. Schválení svázat s verzí a hashem přesného souboru; agent ani provozní obsah jej nesmí měnit nebo automaticky schvalovat. Samotná změna JSON v repozitáři není aktivace.
2. Ověřit syntetickými testy odmítnutí cizího prostoru, neznámého commandu/parametru, redirectu, neplatné relace a nezpárovaného klienta. Ověřit více než 200 záznamů, omezení velikosti, částečné výsledky, selhání stránky a změnu účtu.
3. Po schválení provést nativní aplikací omezený integrační pilot jen na uvedených cílech. Agent nedostane token ani surové odpovědi; nativní diagnostika vrátí pouze pevné výsledky kontrol a počty. Nejprve potvrdit vlastní vazbu a datové kontrakty. Příkaz s neověřeným kontraktem se smí použít pouze v tomto diagnostickém režimu, nikoli jako autoritativní agenda.
4. Zapsat sanitizované výsledky ověření a aktivovat jen položky se splněnými podmínkami. Pokud bude potřeba jiný command, cíl či širší DTO, předložit změnu politiky. Pak teprve připojit normalizované výsledky k pracovní evidenci Iris.

**Schválený rozsah:** čtení vlastní agendy těmito čtyřmi commandy v uvedeném rozsahu a limitech, včetně omezeného ověření jejich kontraktů. Čtvrtý command zůstává podmíněný výsledkem ověření. Žádné pracovní zápisy ani další zdroje toto schválení nezahrnuje.
