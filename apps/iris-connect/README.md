# Iris Connect místní prototyp

**0.6.0 – čtecí kalibrace kalendáře:** pevný příkaz `IrisRead diagnostics.calendarBoundaries` provede pouze schválená čtení. Porovná explicitní UTC hranice pražských dnů, širší okno, aktivní blokující záznamy bez časového filtru, sousední dny, dotazy končící/začínající přesně na existující události a dostupné okno změny času. Vydá jen počty a pevné příznaky. Nezapisuje testovací události a nevydává neověřená kalendářní data běžnému klientovi. Teprve po shodě všech povinných kontrol pro tento běh povolí běžné `calendar.list`; nový login a restart tuto kalibraci ruší. Veřejný interval datumů je včetně obou dnů, interní UTC dotaz je od místní půlnoci do půlnoci po posledním dni a vrácené záznamy se filtrují na polouzavřený interval. Syntetické testy pokrývají 23hodinový a 25hodinový den, nulové události a překryvy. Výsledek živé kalibrace se eviduje odděleně od úspěšného sestavení.

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
