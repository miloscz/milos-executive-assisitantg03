# Pokyny pro práci na Iris

S uživatelem komunikuj česky. Dohodnuté chování je v `docs/architecture.md`, pořadí práce v `docs/implementation-plan.md` a aktuální přihlašovací prototyp v `apps/iris-connect/README.md`.

## Současný rozsah

Místní prototyp i přihlášení při zamčeném Mini jsou ověřené. Po výpadku správy Mini Miloš rozhodl provoz nejprve rozjet na tomto Macu a přenos na Mini dokončit později. Na tomto Macu jsou ověřené Iris Local i přihlášení přes Aidu. Původní plugin Iris Tunel byl po výslovném souhlasu Miloše odinstalován z účtu; aplikace, tunel ani klíče na Mini se neměnily. Místní host používá jiné soukromé ID tunelu. Audit ostatních přímých +4U cest zůstává samostatný. Aida nesmí dostat obecný přístup ani k jednomu počítači; používá výhradně omezené MCP. Přenášej pouze explicitně vybrané zdroje a instalační artefakty, ne klíčenky, tokeny, přístupové kódy nebo staré credential soubory. Aida je jméno komunikační agentky na platformě Dot; Iris je pracovní a znalostní systém.

## Přístupové kódy a přihlašovací relace

Uživatel výslovně zakázal agentům přístup k AC1 a AC2. Tato podmínka platí i při diagnostice, opravách a testech.

- Nikdy nežádej uživatele, aby poslal kódy do chatu, terminálu, souboru, argumentů příkazu nebo proměnných prostředí. Zadává je pouze v nativním okně Iris Connect.
- Nečti položky uživatelské klíčenky, staré tokenové soubory, prohlížečové cookies, `.env` s přihlášením nebo paměť přihlašovacího procesu. Nepoužívej `security find-generic-password` pro získání hodnot, debugger ani dump paměti.
- Po zpřístupnění aplikace uživateli nezískávej snímky, accessibility hodnoty, DOM nebo jiné UI výpisy přihlašovacích oken. Uživatelem probíhající přihlášení neautomatizuj nástroji agenta.
- Nevytvářej CLI, IPC, HTTP, WebKit bridge ani diagnostickou cestu pro import/export kódů, tokenů nebo libovolné spuštění skriptu. Automatické doplnění je výhradně uvnitř nativní aplikace do oficiálního formuláře.
- Neopisuj klientská tajemství z původní konfigurace do repozitáře nebo výstupů nástrojů. Při kontrole zdrojového souboru je rediguj ještě před vrácením obsahu modelu. Aplikace smí převzít potřebné existující klientské konstanty interně při běhu.
- Údaje aplikace patří do Keychain s omezeným přístupem podepsaného buildu. Žádný souborový fallback a žádné zpřístupnění klíčenky všem aplikacím.
- Dokonči kontrolu a sestavení před výzvou k zadání skutečných údajů. Nepřepisuj právě používaný bundle během zadávání kódů nebo přihlášení. Při další úpravě nejprve domluv nebo bezpečně ukonči aktivní pokus; nový build může vyžádat nový souhlas Keychain.
- Chyby a protokolová diagnostika nesmějí obsahovat těla autentizačních odpovědí, citlivé HTTP hlavičky nebo argumenty skriptů s kódy.

Agent smí číst sanitizovaný soubor `~/Library/Application Support/Iris Connect/verification.json`, který obsahuje jen pevné stavy, čas a příznaky ověření. Při čtení validuj typy a známé hodnoty; nevracej libovolný obsah souboru do konverzace.

Po schválení čtecí politiky smí agent také číst `read-verification.json` pomocí `tools/iris-connect-read-status.py`. Obsahuje pouze pevné stavy a počty. Podepsaný a uživatelem místně spárovaný klient `IrisRead` smí vracet normalizovaná pracovní data podle schválené politiky; diagnostický pilot vrací jen kontroly a počty. Žádná z těchto cest nesmí zpřístupnit tokeny nebo přihlašovací údaje. Politika `iris-connect-read-v1` byla výslovně schválena uživatelem 18. října 2026; přesný hash je v `policies/iris-connect-read-v1.approval.json`.

## Zákaz přímého +4U přístupu Aidy

Aida ani její delegované úlohy nikdy přímo nevolají +4U: žádné jiné +4U pluginy, HTTP nástroje, curl ani prohlížeč. Používají pouze omezené rozhraní Iris/Iris Connect a nikdy nedostávají tokeny, kódy, cookies nebo autentizační hlavičky. Tento zákaz je závazný i pro diagnostiku. Současný obecný přístup Aidy k Macu není technickou izolací; před běžným provozem se má nahradit omezeným MCP rozhraním a odstranit ostatní cesty. Nevydávej instrukci za vynucenou síťovou politiku. Přesný místní příkaz IrisControl může vyžadovat samostatné povolení sandboxu pro UNIX IPC; toto povolení se nesmí rozšiřovat na jiné příkazy nebo obcházení zamítnutí. Podrobnosti jsou v docs/architecture.md.

## Omezené MCP a tunel

`services/iris-mcp` zpřístupňuje čtyři pevné řídicí nástroje a od verze 0.2.0 na výslovný požadavek Miloše připravit briefing pro Aidu také `iris_get_morning_briefing`. Pátý nástroj bez parametrů čte pouze pevný soubor `.iris-runtime/morning-briefing.json`, kontroluje vlastníka, práva, velikost, symlinky, přísné schéma, stáří i nepředání tajných údajů. Nevolá +4U, nespouští přípravu ani MFA a neposkytuje obecný přístup k souborům. Provozní data jsou soukromá a ignorovaná Gitem. Spouští se výhradně přes `scripts/run-stdio.sh`, který vymaže zděděné prostředí a použije ověřovaný macOS sandbox bez internetu, obecného čtení uživatelských souborů a obecného spouštění programů. Povolen je pouze přibalený IrisControl, jeho konkrétní UNIX socket a čtení jediného připraveného briefingu. Nepřidávej obecné HTTP, souborové, shellové ani tokenové nástroje. Změna výstupního schématu musí projít kontrolou nepředání tajných údajů včetně chyb SDK.

Aplikace `Iris MCP` je nativní host oficiálního Secure MCP Tunnel. Provozní OpenAI klíč se zadává jen do jejího soukromého pole a patří jen do její vlastní klíčenky; agent nesmí číst hodnoty, UI, clipboard, konfigurace s hodnotami klíčů nebo paměť. Klíč není AC1/AC2 a není to token +4U. Host ho interně předává pouze ověřenému procesu tunnel-client; MCP server dostává prázdné prostředí bez klíče. Sanitizovaný stav lze číst jen přes `python3 tools/iris-mcp-status.py`. Nečti obsah logů tunelu nebo administrátorských exportů. Nenastavuj logování surových požadavků.

Do připojení výhradně soukromého MCP pluginu a živého ověření neprohlašuj Aidu za přepnutou. Po přepnutí musí být odebrán její obecný přístup k Macu a ostatní +4U cesty. Automaticky nevytvářej veřejný tunel nebo sdílený workspace plugin jako náhradu. Ověření připravenosti tunelu samo nedokazuje připojení Aidy. Přístup k registrovaným nástrojům platformy a přímým +4U pluginům se ověřuje samostatně; instrukce nejsou vynucenou síťovou politikou celé platformy Dot.

## Místní ovládání přes Aidu

Verze 0.3.0 přidává podepsaný IrisControl a samostatné párování pro tento běh aplikace. Přesný protokol je v `integrations/aida/README.md`. Stav lze číst přes `IrisControl status`; `prepare` zaznamená skutečně potřebný přístup, ale nevyvolá MFA. `noticeSent` smí následovat až po skutečně odeslaném upozornění. `start` vyžaduje nový přímý lidský pokyn v reakci na toto upozornění, platné noticeID, requestID a příznak přímého pokynu. Žádné automatické starty, opakování po selhání nebo výroba lidského souhlasu. Tento úkol autorizuje implementaci spojení, nikoli spontánní živý MFA pokus. Při timeoutu použít stejné requestID. Nikdy nečíst přihlašovací UI. `auth-workflow.json` neobsahuje tajné údaje, ale agent ho neupravuje; čte stav přes ověřený helper. Párování helperu není důkazem identity Aidy ani lidského původu pokynu.

## Ověření a změny

Od verze 0.5.0 smí nativní Iris Connect na samostatný místní souhlas obnovit párování po spuštění, pouze pokud odpovídají přesné hardened CDHash aplikace i IrisControl. Souhlas se ukládá jen nativní volbou v odemčené aplikaci; agent jej nevyrábí úpravou preferences. Změna verze/podpisu vyžaduje nový místní souhlas. Toto obnovení nikdy neobnovuje notice ani pokyn ke startu a nikdy samo nezahajuje +4U login. Nativní tlačítko kontroly klíčenky může lokálně ověřit přístup pouze aplikací a odstranit její nepoužívanou starou kopii session bez čtení tokenu; není to exportní ani IPC cesta. Host Iris MCP 0.2.0 má samostatnou místní volbu automatického připojení tunelu; při startu čte svůj klíč bez povolené interakce, při chybě končí a neobchází souhlas klíčenky. LaunchAgenty spravuje pouze `tools/deployment/mac-mini-startup.py`, bez tajných údajů nebo rozšíření oprávnění Aidy.

Automatické testy používají syntetická data. Živé MFA potvrzuje člověk. Veřejné discovery, úspěšné sestavení a přihlášení v jiné aplikaci nejsou důkazem živého AC1/AC2 a MFA v Iris Connect. Rozlišuj podepsaný token, úspěšné čtení a uživatelské potvrzení MFA.

Pracovní uuCommandy se povolují až podle schválené sady a podmínek parametrů. První přihlašovací prototyp obsahuje jen pevné autentizační operace a čtecí ověření identity. Původní Iris v `/Users/milosvodrazka/Personal/milos_executive_assistant` se zatím neupravuje ani nevypíná.
