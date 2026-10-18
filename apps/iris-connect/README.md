# Iris Connect místní prototyp

**Historie 0.6.1 – čtecí kalibrace kalendáře:** po chybě pokusu s ISO timestampy používá pouze date-only YYYY-MM-DD. Pražské intervaly obalí UTC dny, přebytečné záznamy filtruje nativně. Pevný `IrisRead diagnostics.calendarBoundaries` porovná širší okno, aktivní blokující záznamy, sousední dny, místní filtr na existující události a dostupný den změny času. Vrátí pouze počty a příznaky; bez shody povinných kontrol nepovolí běžné calendar.list. Nezapisuje testovací události. Prošlo 37 syntetických testů; následný živý výsledek vedl k doplnění 0.6.2 popsanému níže. [Doložené výsledky a limity](../../docs/iris-connect-read-verification.md).

**0.6.2 – rozlišení koncového dne:** kalibrace 0.6.1 potvrdila pokrytí a filtrování, ale nepotvrdila předpoklad serverové UTC půlnoci. Nový pevný test porovná UTC/pražskou půlnoc i zahrnutí celého koncového dne a vrátí všechny shodné modely. Neznámý výsledek nepovolí provozní kalendář. I obalený HTTP dotaz musí dodržet 93denní limit. Prošlo 38 syntetických testů. Živá kalibrace 18. října v 19:17:25 Europe/Prague uspěla; shodují se oba modely celého koncového dne, zónu vzorek nerozlišuje. Běžné calendar.list v této relaci prošlo. Délka dne změny času má 25 hodin, ale bez živých událostí nelze tvrdit test jejich přechodu.

Build `scripts/build-app.sh --stage` připraví nový podepsaný bundle v jedinečné oddělené složce build/staging.*, aniž přepíše běžící aplikaci. K aktivaci je nutné bezpečně ukončit starou verzi a po změně podpisu obnovit místní souhlasy. Žádný token nebo souhlas s MFA se nepřenáší.

Nativní aplikace pro tento Mac. Přijímá AC1 a AC2 pouze v soukromém okně, ukládá je do macOS Keychain a doplňuje je do oficiálního formuláře +4U. MFA zpracovává oficiální stránka; potvrzuje ji uživatel. Verze 0.2 přidává omezené místní čtecí rozhraní pro spárovaného klienta. Neobsahuje obecnou HTTP proxy ani zápisy do úkolů a kalendáře.

Základní živé přihlášení, uživatelské potvrzení MFA, podpis a claims tokenu a následné čtení identity byly úspěšně ověřeny 18. října 2026. Agent při ověřování četl jen sanitizovaný stav, nikoli kódy nebo token. Podrobnosti jsou v [záznamu ověření](../../docs/iris-connect-verification.md).

Ve verzi **0.2.2** byl živě ověřen i průchod bez ruční volby Plus4U Access: po zahájení přihlášení uživatel pouze potvrdil MFA na telefonu. Nativní aplikace sama vybrala metodu, doplnila kódy a ověřila token i čtení identity. Prošlo 24 automatických testů. Zahájení přihlášení přes Aidu zatím není implementované.

Uživatel schválil [čtecí commandy a omezení](../../docs/iris-connect-read-policy.md). Původní specifikace `policies/iris-connect-read-v1.draft.json` zůstává beze změny; [záznam souhlasu](../../policies/iris-connect-read-v1.approval.json) určuje její schválený hash. Aplikace ověřuje přibalenou kopii proti tomuto hashi a jednotlivé operace omezuje nativním kódem.

## Čtení úkolů a kalendáře

1. Po přihlášení zvol **Najít můj pracovní prostor**. Aplikace použije pouze `people/findPerson` pro přihlášenou identitu.
2. Zkontroluj vlastní workspace v nativním okně a zvol **Potvrdit vlastní prostor a místního klienta**. Tím se spáruje přibalený podepsaný `IrisRead` pro tento běh aplikace. Nevznikne síťový listener.
3. Zvol **Ověřit čtení úkolů a kalendáře**. Pilot načte aktivní záznamy bez časového filtru, diář a finální záznamy v povoleném okně. Zobrazuje jen počty a pevné stavy; nijak nemění pracovní agendu.
4. Sanitizovaný výsledek pro agenta čti přes `python3 tools/iris-connect-read-status.py`. Nečti přihlašovací UI ani jiné provozní soubory aplikace.

Po párování lze použít místního klienta:

```sh
"build/Iris Connect.app/Contents/MacOS/IrisRead" status
"build/Iris Connect.app/Contents/MacOS/IrisRead" diagnostics.verifyReads
"build/Iris Connect.app/Contents/MacOS/IrisRead" tasks.listActive
```

Výsledky provozního čtení jsou normalizované JSON, nikoli surová odpověď nebo token. Neověřené kontrakty vracejí `contractPending`; diagnostický pilot z nich vrátí pouze počty a pevné kontroly. [Stav a zbývající ověření](../../docs/iris-connect-read-verification.md) rozlišují funkční čtení a doloženou úplnost kalendáře či význam finálních stavů. Zamčení, nové přihlášení a expirace ruší párování. Aida a služba `iris-core` zatím připojené nejsou.

## Sestavení a spuštění

Vyžaduje macOS 14 nebo novější a Xcode se Swift 6. V kořeni repozitáře spusť:

```sh
apps/iris-connect/scripts/build-app.sh
open "build/Iris Connect.app"
```

Skript sestaví release aplikaci, opatří ji místním ad hoc podpisem a zapne hardened runtime bez debugger entitlementu. `swift run` není podporovaná cesta pro skutečné údaje; přístup ke klíčence vyžaduje hardened build. Není potřeba Apple Developer certifikát. Ad hoc podpis není distribuční nebo notarizovaný podpis.

## Ruční ověření přihlášení

1. Agent nejprve dokončí kontrolu zdrojů a sestavení. Při zadávání skutečných údajů už nesnímá okna, nečte jejich obsah a nepoužívá UI automatizaci přihlášení.
2. V aplikaci zvol **Zadat přístupové kódy**, oba kódy napiš přímo do soukromého okna a ulož je do klíčenky. Neposílej je do chatu, terminálu ani souboru.
3. Zvol **Přihlásit a ověřit čtení**. Verze 0.2.2 sama jednou zvolí Plus4U Access, pokud je místo přístupových kódů otevřený výběr metody. Rozpoznává české a anglické varianty vykresleného popisku na přesné oficiální přihlašovací stránce; případný odkaz musí zachovat stránku i parametry přihlášení. Na správný formulář čeká nejvýše jednu minutu. Výsledky živého ověření jsou v [záznamu přihlášení](../../docs/iris-connect-verification.md).
4. Aplikace doplní obě pole a jednou odešle oficiální formulář. Dále dokonči MFA na oficiální stránce / telefonu. Neúspěšné údaje automaticky znovu neodesílá.
5. Po návratu aplikace ověří podpis a claims ID tokenu a provede pevně určené čtení `oidc/getIdentity`. Teprve pak zobrazí úspěšně ověřenou relaci a uloží token do klíčenky.
6. Pokud jsi skutečně dokončil MFA, zvol **Potvrzuji, že jsem dokončil MFA**. Tento údaj je výslovně uživatelským potvrzením, nikoli tvrzením, že aplikace kryptograficky ověřila druhý faktor.
7. Zmeškaný nebo zrušený pokus spusť znovu stejným tlačítkem. Jeden pokus platí nejvýše pět minut. Zamčení Macu probíhající pokus zruší.

Tlačítko s potvrzením MFA je volitelný diagnostický záznam po přihlášení; není další podmínkou úspěšného přihlášení. Při ověření režimu „po zahájení už jen telefon“ na něj neklikej a skutečný průběh potvrď v konverzaci. Jednorázový systémový souhlas Keychain po změně podepsaného buildu je samostatná otázka macOS.

Tlačítko **Zapomenout údaje** odstraní kódy a token této aplikace z klíčenky. Neprovádí globální odhlášení jiných +4U aplikací.

## Co aplikace přebírá ze současné Iris

Načítá pouze konstanty OIDC klienta ze zdrojového souboru původní Iris:

```text
/Users/milosvodrazka/Personal/milos_executive_assistant/mcp-servers/iris-dwg-mcp/src/oidc.js
```

Zdrojový JavaScript nespouští. Přebírá existující konfiguraci klienta pro místní ověření kompatibility; nekopíruje klientské tajemství do tohoto repozitáře. Nikdy nečte původní `credentials.json`, `.env`, staré tokeny ani uživatelské přístupové kódy. Změna nebo redistribuce klienta není předmětem prototypu.

Původní Iris implementuje Authorization Code přes prohlížeč. Neobsahuje hotovou přímou implementaci AC1/AC2 s MFA. Prototyp zachovává tuto cestu, přidává PKCE S256, `state`, `nonce` a kontrolu podpisu tokenu. Formulář běží v odděleném nepersistentním WKWebView; heslový grant bez MFA není použitý.

## Hranice přístupu k tajným údajům

- Obě vstupní pole jsou `NSSecureTextField`; hodnota není poskytována přes accessibility getter. Uložené kódy se nikdy nevracejí do UI. Není zde tlačítko pro odhalení nebo export.
- Kódy se ukládají jako jeden atomický záznam v Keychain s ACL vytvářející podepsané aplikace. Neexistuje plaintextový fallback ani synchronizace těchto položek přes iCloud.
- Kódy v paměti dostává pouze interní nativní kód a oficiální přihlašovací stránka v okamžiku odeslání. Nenacházejí se v argumentech procesu, proměnných prostředí, IPC, konfiguračním souboru ani diagnostice.
- WebView nemá zapnutý Web Inspector ani nativní script message handlery. Doplňování se povolí pouze hlavnímu dokumentu na přesném login originu a cestě, pro správná pole a POST formulář směřující na stejný origin do `authAccessCodes/authenticate`.
- Nativní volba Plus4U Access používá jen pevný skript a přesné známé popisky. Nekliká na submit, skryté, zakázané nebo nejednoznačné tlačítko, jiného poskytovatele ani MFA. Do nativního kódu vrací pouze pevné stavy. Pokud se stránka změní, pokus skončí pevnou chybou `loginMethod`; nezískává obecné oprávnění ovládat stránku.
- Autorizační návrat zachytává navigační delegát. Aplikace neotevírá lokální TCP callback server. Kontroluje přesnou callback adresu, stav, expiraci a duplicitní parametry.
- Tokenové požadavky mají pevné adresy. HTTP redirecty se nepřebírají, chyby neobsahují těla odpovědí ani argumenty WebKitu. ID token musí mít platný RS256 podpis vůči klíčům pevného issueru a očekávaný issuer, audience, nonce a časové claims.
- Audience musí obsahovat aktuálního klienta a pouze důvěryhodné další hodnoty: issuer a explicitně požadované cíle z konfigurace původní Iris. Volitelné `azp` se při přítomnosti musí shodovat s klientem; jeho absence u více audience není sama o sobě chyba.
- Aplikace nepředává token žádnému agentovi. Pracovní čtení vynucuje schválenou pevnou sadu commandů, vlastní potvrzený prostor a identitu procesu místního klienta.

Keychain a hardened runtime tvoří ochranu vůči jiným procesům; nejsou absolutní zárukou proti správci počítače, kompromitovanému OS nebo uživatelem schválenému škodlivému buildu. Lokálně spuštěný agent má právo měnit zdrojový kód, proto musí být kontrola a sestavení hotové před zadáním údajů. Po změně buildu může Keychain vyžádat nový souhlas. Přístup k těmto položkám z terminálu, jiných aplikací nebo debuggeru se nemá schvalovat. Tento prototyp nezavádí samostatný macOS uživatelský účet ani hardwarově oddělenou bezpečnostní doménu.

## Bezpečný stav pro ověření

Aplikace zapisuje pouze sanitizovaný stav do:

```text
~/Library/Application Support/Iris Connect/verification.json
```

Záznam obsahuje stav, čas, konec platnosti a booleany ověření podpisu, skutečného čtení, doplnění formuláře a ručního potvrzení MFA. Verze 0.2.1 přidává `accessMethodSelectionAttempted` a `accessMethodSelectedByApp`; jde pouze o příznaky nativní volby metody. Neobsahuje identitu, kódy, tokeny, URL s parametry ani obsah odpovědí. Tento soubor je určený i pro přečtení agentem. Není důvěryhodným auditním důkazem proti místnímu útočníkovi a není provozním API Iris.

Při odmítnutí tokenu obsahuje pouze pevně definované kódy nesplněných podmínek, nikdy hodnoty claims. Bezpečné čtení stavu z kořene projektu:

```sh
python3 tools/iris-connect-status.py
```

## Automatické testy

```sh
CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/module-cache" \
swift test --disable-sandbox --package-path apps/iris-connect --scratch-path build/swift-test
```

Testy používají syntetická data a dočasný RSA klíč. Nezadávají ani nečtou AC1/AC2 a nepřistupují k položkám klíčenky aplikace. Ověřují PKCE, ochranu callbacku, omezení cílových adres, parsování konfigurace a skutečnou kontrolu podpisu a claims JWT. Vnější sandbox může zablokovat systémovou kryptografickou službu i pro dočasný klíč; tehdy je potřeba test spustit mimo tento sandbox.

## Limity první verze

Živé AC1/AC2 a MFA vyžadují účast uživatele. OIDC discovery a veřejný formulář samy nedokazují úspěšné přihlášení konkrétního účtu. Embedded web flow může poskytovatel změnit nebo zablokovat; nejedná se o nový garantovaný veřejný API kontrakt. Obecné doporučení OAuth pro nativní aplikace preferuje systémový prohlížeč, který však této aplikaci neumožňuje přímo doplnit vlastní Keychain položky. Tento místní prototyp proto explicitně ověřuje kompatibilitu existující cesty v soukromém WebView.

Verze 0.3.0 přidává samostatný podepsaný klient IrisControl pro místní úlohu Aidy: stav → potřeba přístupu → odeslané upozornění → nový přímý pokyn → jeden pokus. Rozhraní funguje i bez platného tokenu a má samostatné párování v nativním okně. [Nastavení a protokol Aidy](../../integrations/aida/README.md) popisuje přesný postup a dosud neověřený živý průchod. Není implementovaný push do Aidy ani trvalý scheduler. Pracovní zápisy a obnova tokenu po restartu nejsou implementované. Čtecí commandy mají samostatný integrační pilot a podmínky aktivace. Nové přihlášení může zahájit i uživatel tlačítkem v aplikaci.

Zdrojová verze **0.4.0** připravuje Mac mini: místní opt-in pro přihlášení přes MCP při zamčené obrazovce, neinteraktivní klíčenku v tomto režimu a nativní jednorázové převzetí konfigurace původního přihlašovacího klienta. Při odmítnutí klíčenky se pokus zastaví; žádný souborový fallback ani opakované spuštění MFA. Nastavení zámku neznamená podporu odhlášeného uživatele nebo automatického obnovení po restartu. Živý průchod při zamčení zatím není ověřený. Vývoj zůstává na tomto Macu; cílovým trvalým hostem má být Mac mini podle [postupu nasazení](../../docs/mac-mini-deployment.md).

## Obnovení po spuštění – 0.5.0

V odemčeném místním okně lze po povolení IrisControl zapnout „Obnovit toto párování po spuštění aplikace“. Ukládají se pouze veřejné CDHash aktuální hardened aplikace a helperu; při změně kteréhokoli podpisu je potřeba nové místní povolení. Vypnutí ovládání zruší i uložený souhlas. Agent souhlas nevytváří změnou preferences.

Obnovení otevírá jen úzký řídicí socket. Nespouští přihlášení, neobnovuje starý token a nepřenáší staré upozornění ani souhlas se startem. Každý login dál vyžaduje nové upozornění a nový přímý lidský pokyn.

Tlačítko „Ověřit přístup aplikace ke klíčence“ je jen místní UI: nativně zkusí přístup ke klientské konfiguraci a uloženým kódům a žádnou hodnotu nevrací. Pokud tento běh nemá ověřenou relaci, odstraní nepoužívanou starou Keychain kopii session bez čtení tokenu, aby další login nevázal starý ACL podpis. Aktivní ověřenou relaci ponechá. Může vyžádat systémový souhlas pro novou podepsanou verzi; nevytváří MFA ani síťový požadavek. Neexistuje CLI/IPC varianta této kontroly.

Čtecí IrisRead párování a potvrzení vlastního prostoru zůstávají samostatné a neobnovují se automaticky po nové relaci. Čtyři nástroje MCP zatím neposkytují pracovní agendu.


## Čtecí podklady 0.7.0

Rozšíření `iris-connect-briefing-sources-v1` Miloš výslovně schválil 18. října včetně uuManagementKit `keyTask` a `request`; záznam a výsledný hash jsou v `policies/iris-connect-briefing-sources-v1.approval.json`. Přibalená specifikace musí odpovídat hashi zkompilovanému v `SourcePolicy`. Dosavadní DW politika se nemění.

Podepsaný IrisRead má dvě nové pevné operace bez parametrů: `diagnostics.sources` a `sources.prepare`. Nejde o nové nástroje Aidy. První provede omezené čtení a vrací jen pevné kontroly a počty pro Elementary meeting a čtyři typy ManagementKit. Druhá vrací pouze normalizované podklady již ověřených typů; chybějící typ zůstává zavřený. Obě vybírají zdroje nativně z čerstvého vlastního DW a ověřeného kalendáře, nemají URL, command, souborové ani tokenové argumenty. Nejprve musí v aktuální relaci projít `diagnostics.calendarBoundaries`. Čtení zdrojů samo nezahajuje přihlášení.

Místní volba „Obnovit čtecí párování po příštím přihlášení“ je dostupná pouze v odemčené aplikaci po potvrzení prostoru a IrisRead. Uchovává veřejné hashe podpisů, hash identity a potvrzenou adresu vlastního prostoru. Po novém ověřeném loginu aplikace znovu načte vlastní profil a porovná všechny čtyři vazby; změna účtu, prostoru nebo buildu vyžaduje nové místní potvrzení. Neobnovuje relaci ani souhlas s MFA. Zdrojové a kalendářní kontrakty se po novém loginu ověřují znovu.

Před živým pilotem 0.7.0: jednou zamknout/odemknout Mac, místně ověřit přístup ke klíčence, povolit místní ovládání a obnovu jeho párování, sám se přihlásit a potvrdit MFA, najít a potvrdit vlastní prostor i IrisRead a zapnout obnovu čtecího párování. Agent nečte přihlašovací UI ani údaje. Automatizace a nové obsahové karty jsou následně nasazené; aktuální důkazy a omezení jsou v `docs/briefing-automation.md`.


### Ověřená 0.7.1

Oprava přijímá chybějící echo OID v odpovědi Elementary stránky, ale odmítá přítomné rozporné OID. Kalibrace vybírá obsazený den ze společného vzorku místo pevného zítřka, takže prázdná sobota sama nezablokuje páteční přípravu. Prošlo 46 ConnectCore a 11 nativních testů. Po novém místním souhlasu člověka pracovní fronta navázala na čekající úlohu. Všechny čtyři kontrakty ManagementKit prošly živým pilotem; Elementary meeting dál vrací schemaMismatch a jeho texty zůstávají blokované. Není prokázané, že příčinou je právě echo nebo tvar stránky; další diagnostika nesmí uvolnit neznámé serverové warnings. Žádný další build se během uživatelského přihlášení nenasazoval.


### Diagnostika Elementary Management – 0.7.2

Nový build nemění povolené commandy nebo jejich parametry a neignoruje serverové warnings. Pro Elementary rozlišuje validaci identifikátorů, odpověď meeting/load, odpověď meeting/page/load a převod sekcí. Pevná diagnostika navíc rozliší contentType, jsonObject, serverWarnings a targetIdentifiers. Vracet může jen booleany a známé názvy schválených parametrů z enumu; nikdy zprávy serveru, neznámé názvy, hodnoty nebo tělo odpovědi. Neplatná mapa warnings se odmítá. Diagnostická chyba se neopakuje jako síťový timeout.

Prošlo 46 Core + 14 Native syntetických testů, včetně odmítnutí serverových warnings a nezpřístupnění jejich soukromých hodnot. Oddělený hardened build byl ověřený a nainstalovaný až po kontrole busy=false a ukončení aplikace; předchozí 0.7.1 zůstala v build/backups. Čeká se na nový místní souhlas člověka a živý pilot; samotné nasazení zatím nedokazuje opravu čtení schůzek.


### Oprava aliasů Elementary Management – 0.7.4

Jednorázově schválený pilot zjistil technický název unsupportedKeys na meeting/page/load. Rozšířený export názvů je odstraněný ze zdrojů i buildu. Nadále se nevracejí zprávy, hodnoty nebo surové odpovědi.

Nativní pilot rozpozná přesnou strukturu standardního varování unsupportedKeys (také bez prefixu namespace). Pouze v pilotu smí ověřit druhý, užší GET stejného commandu: odstraní výhradně explicitně odmítnuté aliasy z již schválené šestice, zachová alespoň jednu přesnou vazbu na schůzku, stránku a BID, stejné identifikátory i cíl. Nejde o povolení jiného commandu, nové query položky nebo rozšíření čtecí politiky. Obsah první odpovědi se nepoužije. Druhá odpověď musí projít celou kontrolou a nesmí obsahovat varování; neprovádí se další vyjednávání ve smyčce. Neznámá pole, jiná varování, error severity nebo ztráta některé vazby zůstávají chybou.

Ověřená užší sada se drží jen v paměti pro právě ověřenou identitu a expiraci relace; běžné čtení ji může použít, ale samo nic nekalibruje. Nová relace ji nezdědí. Oba požadavky započítávají původní limity, rozpočet a frekvenci. Prošlo 46 Core a 17 Native syntetických testů včetně odmítnutí nebezpečného zúžení, maximálně jednoho kalibračního kroku a oddělení nové relace. Živý pilot opravné verze ještě čeká.


### Kompaktní odpověď Elementary – 0.7.5

Živý pilot 0.7.4 po místním přihlášení dál odmítl odpověď `elementaryPageRequest/serverWarnings`; ManagementKit meeting/document/keyTask/request prošly. Standardní struktura `unsupportedKeys` tedy sama opravu nedoložila.

0.7.5 rozpoznává i omezené kompaktní seznamy/mapy známých aliasů. Prázdný seznam či prázdná mapa pod přesným `unsupportedKeys` v EM odpovědi znamená prázdná metadata, nikoli skutečné varování. Jakákoli jiná položka, neznámý parametr, zpráva místo struktury nebo závažnost error zůstává odmítnutá. Pokud server výslovně odmítne všechny aliasy stránky a BID, pilot smí ověřit pouze hlavní stránku stejné schůzky; vrácené OID i BID pak musejí přesně odpovídat předchozímu detailu. Bez tohoto důkazu se text nevydá.

Pevná diagnostika může navíc vrátit 12 omezených počtů tvarů kontejnerů (`warningShape`), nikoli jejich obsah nebo libovolné názvy. Dočasný export technických názvů zůstává odstraněný. Prošlo 46 Core + 20 Native syntetických testů. Podepsaný 0.7.5 je nasazený se zachovanou zálohou 0.7.4; schválené politiky jsou beze změny. Živý důkaz nové opravy a obnova briefingu čekají na místní souhlasy pro tento podpis.


### Dokumentovaný seznam odmítnutých klíčů – 0.7.6

0.7.5 živě neprošel: pevná diagnostika ukázala objekt paramMap bez dosud podporovaných kontejnerů. Lokální dokumentace uuAppServer (`errors-and-warnings.md`, část uuAppErrorMap) uvádí paramMap.unsupportedKeyList. 0.7.6 rozpoznává tento dokumentovaný seznam při zachování stejného omezení aliasů, vazeb a jednorázového pilotního zúžení. Neznámé parametry nebo error severity zůstávají chybou. Prošlo 66 syntetických testů; živý důkaz 0.7.6 zatím chybí.
