# Omezené MCP Iris pro Aidu

**Oprava 0.5.1:** stalePreparation nyní objedná obnovu pouze existujícího podkladu a zneplatní odmítnutý návrh rozhodnutí. Před novým potvrzením je nutný nový návrh, readback a nový lidský pokyn. Počet nástrojů, schémata a limit stáří se nemění; žádné automatické MFA. [Ověření](../../docs/aida-work-handoff.md#oprava-stalepreparation--051).

**Server 0.5.0:** deset nástrojů včetně `iris_request_preparation_revision`, `iris_prepare_decision`, `iris_confirm_decision` a `iris_get_work_request`. Nové nástroje používají jediný pevný pracovní UNIX socket; MCP nezískává databázi, soubory, síť nebo další program. Rozhodnutí vyžaduje readback a nové lidské potvrzení deklarované Aidou a neopravňuje externí provedení. Prošlo 20 MCP testů. [Kontrakt a živé důkazy](../../docs/aida-work-handoff.md). Níže jsou historické verze.

**Server 0.4.0, host 0.2.1:** přibyl šestý omezený nástroj `iris_get_preparation_detail` pro navazující otázky nad připravenou položkou aktuálního briefingu. Přijímá jen ID a pevné téma, čte jediný další publikovaný soubor `briefing-details.json` do 64 KiB. Nemá přístup k pracovní databázi, zdrojovým snapshotům, libovolným souborům ani +4U. Kontroluje soulad s aktuálním briefingem, stáří, schéma a citlivé hodnoty; neposkytuje obecné modelové nebo shellové volání. Prošlo 17 testů. Miloš potvrdil šest nástrojů po obnovení existujícího Iris Local. [Přesná pravidla a živé ověření](../../docs/stable-binding-and-followup.md). Starší oddíly níže jsou historie.

**Aktuální server 0.3.0, nativní host 0.2.1:** stále pět stejných nástrojů. Briefing nyní obsahuje nejvýše 14 přípravných karet s rozlišením contextOnly / sourcesLoaded / prepared, konkrétními otázkami, chybějícími vstupy a citacemi; prepared vyžaduje doložení. Pevný workflow stav ukazuje přípravu, čekání nebo částečné dokončení. Striktní schéma, limit 24 KiB, filtr tajných údajů, stáří, práva a skutečný OS sandbox zůstávají. Kód jádra ani jeho zdrojové snapshoty nejsou dostupné MCP procesu. Uspělo 15 testů a živé čtení nových karet přes stdio i cloudový Iris Local. [Provoz a uložený rozvrh](../../docs/briefing-runbook.md).

**Verze 0.2.0:** na požadavek prvního ranního briefingu přibyl pátý nástroj `iris_get_morning_briefing` bez parametrů. Čte jediný připravený soubor `.iris-runtime/morning-briefing.json`, nikoli zdrojové snapshoty nebo libovolné cesty. Neprovádí +4U volání, nevyvolává přípravu ani MFA, nespouští nový program. Kernel sandbox povoluje čtení pouze této konkrétní položky vedle dosavadního kódu/helperu/socketu; zbytek uživatelských dat, Internet a obecné procesy zůstávají zakázané. Výstup kontroluje vlastníka, práva, symlinky, velikost do 24 KiB a striktní schéma bez neznámých polí či přihlašovacích hodnot. Stáří nad 30 minut se označí `stale`; neúplný kalendář `activeRecordsOnly`. [Příprava a limity](../iris-core/README.md). Historické záznamy o čtyřech nástrojích níže popisují verzi 0.1.0.

Po restartu serveru se musí obnovit metadata soukromého pluginu. V aktuálním českém rozhraní uživatel ověřil cestu ChatGPT → Pluginy → Iris Local → Spravovat → Znovu načíst nástroje; nejde o nabídku tří teček, která obsahuje odinstalaci a smazání. Po dokončení se musí skutečně ověřit pět nástrojů. První obnovení katalogu stále ukazovalo čtyři; po novém připojení hosta a obnovení katalogu Miloš potvrdil pět nástrojů. Místní skutečné čtení nového briefingu s ověřeným kalendářem uspělo; Miloš po opravě hosta 0.2.1 potvrdil, že hlavní Aida vypsala stručný ranní briefing. Místní katalog ani ready tunelu samy úspěch cloudového volání nedokládají. [Oficiální postup OpenAI](https://developers.openai.com/plugins/deploy/connect-chatgpt#refresh-metadata). Následuje skutečné volání `iris_get_morning_briefing` z pluginu a přímo Aidou; úspěch místního stdio sám nedokládá předání Aidou. API klíč ani +4U údaje se při Refresh nezadávají.

## Oprava souběžných starých instancí – host 0.2.1

Aida 18. října v 19:19 ohlásila invalidRequest při čtení briefingu; stejný výsledek se podařilo zopakovat skutečným cloudovým pluginem, zatímco místní stdio uspělo. Metadata procesů ukázala tři osiřelé staré tunnel-client procesy (od 18:09, 18:45 a 18:55) s vlastními MCP potomky vedle aktuálního hosta. Kontrolovaly se pouze PID, rodiče, čas a název programu, nikdy argumenty, prostředí, paměť nebo klíče. Staré instance byly přesně vybrané a ukončené. Po čistém připojení uspěl i skutečný cloudový briefing. To podporuje diagnózu smíšených starých a nových serverů; surový provoz ani logy se kvůli tomu nezapínaly.

Host 0.2.1 přidává soukromý flock host.lock proti druhé instanci a obsluhu SIGTERM/SIGINT přes běžné ukončení aplikace. Stop ukončuje celou samostatnou procesní skupinu oficiálního klienta včetně stdio potomka a nechá jej dokončit úklid health souboru před dalším startem. Signál se neposílá cizí nebo vlastní skupině hosta. Neúspěšná druhá instance nečte klíčenku a nepřepisuje stav první. Nouzové SIGKILL hosta nemůže spustit jeho obsluhu ukončení; běžný launchctl restart je doložený níže. Do MCP nepřibyl žádný procesní nebo souborový nástroj.

Test `python3 apps/iris-mcp-host/scripts/test-lifecycle.py` používá jen dočasné syntetické procesy: SIGTERM i SIGINT ukončí worker a potomka, druhý host je odmítnut a po ukončení jde zámek znovu získat. Pět testů sanitizovaného stavu také prošlo. `apps/iris-mcp-host/scripts/build-app.sh --stage` sestaví a podepíše oddělený bundle bez přepsání běžící aplikace.

Podepsaný host 0.2.1 byl bezpečně nasazený. Živý launchctl bootout odstranil všechny tři jeho procesy (host, klient, Node) bez ručního úklidu; po bootstrap vznikla jediná nová trojice. Tunel znovu hlásí ready. Přechodný první cloudový požadavek po restartu měl timeout; následný stav a briefing přes skutečný Iris Local uspěly. Přesnou příčinu přechodného timeoutu nepovažujeme za doloženou. Cloudový briefing: ok=true, freshness=current, date=2026-10-19, coverage=verified, 11 bloků, tři priority, dva konflikty; nejstarší zdroj 19:17:13 Europe/Prague. Connect 0.6.2 i jeho relace zůstaly beze změny, nový souhlas klíčenky ani MFA nebyly potřeba. Miloš následně potvrdil, že Aida vypsala stručný ranní briefing. To dokládá textové předání po opravě, nikoli hlasový průchod nebo samostatnou kontrolu všech vět její odpovědi.

Implementace 0.1.0 na tomto Macu. MCP server používá oficiální SDK, stdio a podepsaného místního IrisControl. Neobsahuje HTTP server ani přímého klienta +4U. Nativní Iris Connect zůstává jediným vykonavatelem autentizace a schválených +4U operací.

Aktuálně se na pokyn Miloše nejprve obnovuje provoz na vývojovém Macu a přenos na Mini se dokončí později. [Stav obou hostů](../../docs/mac-mini-deployment.md). Výstup stavu nově připouští pouze booleovský `backgroundLoginEnabled`; starší nativní build se považuje za nepovolený. Změna nepřidává žádný nástroj, síťový cíl ani datový přístup. Launcher vybírá Node pouze ze dvou pevných instalačních umístění.

## Místní provoz při nedostupné správě Mini

Na vývojovém Macu se používají stejné ověřené podepsané bundle Connect 0.5.0 a MCP host 0.2.0. Nový build není pro tuto změnu potřeba. Spouštění po přihlášení do Aqua relace instaluje `python3 tools/deployment/mac-mini-startup.py install --target current-mac`; kontrola je `status --target current-mac`, odebrání těchto dvou úloh `remove --target current-mac`. Výchozí cíl bez přepínače zůstává Mini. Povolené jsou jen dva přesné účty a umístění projektu, žádný libovolný instalační cíl. Souhlasy pro Keychain, párování a automatické připojení zůstávají výhradně v nativním okně.

Protože Mini stále odpovídá přes původní soukromý tunel, tento Mac musí použít **nový soukromý tunel Iris Local**, nové ID a samostatný provozní klíč Read + Use zadaný člověkem pouze do Iris MCP. Původní ID Mini se zde nepoužije. Klíče ani Keychain se z Mini nekopírují. V ChatGPT se pro tento tunel vytvoří samostatný soukromý plugin **Iris Local**. Před přepnutím Aidy se místně a přes nový plugin ověří stejné čtyři nástroje a stav. Poté Aida dostane přímý pokyn používat Iris Local a vrátí skutečný stav tohoto nástroje. [Oficiální dokumentace](https://learn.chatgpt.com/docs/dots/computers-and-apps) popisuje použití pluginů instalovaných a povolených pro účet; samostatný seznam pluginů v profilu Aidy není ověřený. Odebrání dostupnosti starého pluginu je samostatný krok v nastavení pluginů po ověření rozsahu změny. Pokyn Aidě není technické odebrání oprávnění. Obecný přístup k počítači se neobnovuje.

Místní spuštění a syntetické testy samy nedokládají přepnutí Aidy. První živé MFA přes nový plugin potřebuje nové skutečně doručené upozornění a následný přímý lidský pokyn. Přenos zpět na Mini bude řízené předání jediného aktivního připojení Aidy, s novým ověřením a místní konfigurací klíčenky, bez přenosu tajných hodnot.

## Rozsah

| Nástroj | Povolený účel |
| --- | --- |
| `iris_get_access_status` | Pevný stav přístupu bez síťového volání +4U. |
| `iris_prepare_login` | Připravit skutečnou potřebu přístupu; nevytváří MFA. |
| `iris_confirm_notice_sent` | Zaznamenat skutečně odeslané upozornění hlavní Aidou. |
| `iris_start_login` | Jeden pokus po novém přímém lidském pokynu, s platným noticeId a idempotentním requestId. |

Tato verze nepřidává čtení agendy, briefingy ani zápisy do +4U. Čtecí politika Iris Connect se nemění. Start se v integračních kontrolách nevolá. Pole `userCommand` je deklarace volajícího, nikoli důkaz lidského souhlasu; nativní aplikace vynucuje platné upozornění, pořadí, jednorázovost a expiraci. Anotace MCP samy nenahrazují autorizaci.

## Technické omezení rozhraní

- Striktní vstupní schémata. Žádné URL, hlavičky, souborové cesty, shell, libovolné procesy, cookies nebo tokeny. Nejsou publikovány MCP resources, prompts, sampling ani sběr tajných údajů přes elicitation.
- Backend smí spustit jen konkrétní přibalený IrisControl s pevným seznamem argumentů, bez shellu, s omezením času a délky výstupu. Nativní aplikace ověřuje přesný hardened podpis klienta; klient ověřuje konektor.
- Výstup se skládá z povolených příznaků, UUID, pevných fází a času. Text upozornění je vlastní konstanta; libovolný nativní text se nepřebírá. Neznámá pole, neplatné typy, neočekávané chyby a nadlimitní odpovědi skončí pevnou chybou. Totéž platí pro validační chyby MCP SDK; nesmějí odrazit vstupní hodnoty či názvy.
- Spouštět **výhradně** přes `scripts/run-stdio.sh`. Launcher vymaže prostředí (včetně provozního klíče tunelu) a aktivuje macOS sandbox: zákaz veškeré sítě s jedinou výjimkou konkrétního UNIX socketu `auth.sock`; zákaz čtení a zápisu uživatelských souborů kromě čtení kódu a podepsaného helperu; zákaz spouštění jiných programů. Metadata cest jsou povolená kvůli načítání Node modulů. Sandbox neomezuje samostatný proces Iris Connect.
- Maximálně dva současné nástrojové požadavky, 60 nástrojových volání za minutu na proces, 32 KiB na vstupní zprávu a 8 KiB na odpověď nativního řídicího klienta. Tunel má další vlastní limity. Nativní konektor nadále vynucuje svůj limit přihlašovacích pokusů.
- Sandbox je ověřený na tomto Macu, používá místní `sandbox-exec`; nesmí se tiše vypnout při chybě. Není to slib přenositelnosti na jinou verzi macOS. Vývojový kód zůstává v tomto repozitáři; izolace se vztahuje na proces MCP a jeho klienta, nikoli na libovolný jiný proces se stejnými oprávněními uživatele.

## Místní ověření

```sh
npm ci --ignore-scripts --prefix services/iris-mcp
npm test --prefix services/iris-mcp
node services/iris-mcp/scripts/smoke.mjs
```

OS sandboxové testy a přístup k UNIX IPC mohou vyžadovat povolení přesného příkazu mimo vnější sandbox Codexu. To nevypíná vnitřní sandbox MCP. Smoke provádí pouze inicializaci, seznam nástrojů a `iris_get_access_status`; nikdy nevyvolá MFA. Testy používají syntetické hodnoty a lokální testovací socket, ne skutečné tokeny nebo produkční +4U.

## Nativní host soukromého tunelu

Aplikace `build/Iris MCP.app` spouští oficiální OpenAI tunnel-client a potřebuje zůstat otevřená. Její kód je v `apps/iris-mcp-host`. Secure MCP Tunnel otevírá pouze odchozí spojení; soukromý MCP nemá veřejný posluchač. Místní administrace klienta je pouze na loopbacku a není nástrojem Aidy.

```sh
python3 apps/iris-mcp-host/scripts/fetch-tunnel-client.py
bash apps/iris-mcp-host/scripts/build-app.sh
```

Instalátor stahuje oficiální aktuální vydání a před extrakcí ověřuje zveřejněný SHA-256. Při prvním ověření šlo o verzi 0.0.16 pro arm64. Build je místně ad-hoc podepsaný s hardened runtime; update může vyžádat nové potvrzení klíčenky. Běžící host nelze přepsat sestavovacím skriptem.

Host má **vlastní oddělenou** položku Keychain pro provozní API klíč OpenAI, bez přístupu k položkám Iris Connect. Přijímá jen tvar provozního OpenAI klíče, nikoli AC1/AC2 či token +4U. Hodnotu dostane pouze interní proces oficiálního tunnel-client přes jeho procesní prostředí; není v argumentech, souborech, repozitáři nebo MCP odpovědích. Následný MCP launcher prostředí vymaže. Soubor `transport.yaml` obsahuje pouze referenci `env:CONTROL_PLANE_API_KEY`. Vstup je soukromé nativní pole bez accessibility hodnoty. Agent nesmí po otevření získávat snímky, accessibility, clipboard, obsah klíčenky, procesní paměť nebo výpis prostředí této aplikace. Logy transportu jsou zahazované, nepoužívat exporty a logování surových požadavků.

Připravenost host čte jen z loopback `/readyz`, bez cookies, proxy a redirectů. Agent čte pouze pevnou sanitizovanou diagnostiku přes:

```sh
python3 tools/iris-mcp-status.py
```

Host od 0.1.2 vrací také pevný diagnostický enum `failure` (např. `keyMissing`, `keychainDenied`, `configurationWrite`, `clientLaunch`). Žádný klíč, OS chybový text nebo obsah odpovědi. Validátor přijímá staré i nové schéma a odmítá neznámá pole, neznámé kódy a rozpornou připravenost.

Host 0.1.3 nativně normalizuje pouze okolní whitespace v novém i uloženém klíči; vnitřní neplatné znaky odmítá. Hodnoty se agentům nikdy nevracejí.

Host 0.1.4 opravuje nekompatibilní escapování lomítek v generovaném YAML. `python3 apps/iris-mcp-host/scripts/test-config.py` ověřuje skutečný výstup Swift generátoru pomocí `tunnel-client doctor` s izolovaným dočasným HOME a smyšleným klíčem; zároveň dokládá odmítnutí původního zápisu. Nečte provozní konfiguraci, klíčenku ani logy a nespouští tunel nebo MFA.

`ready=true` znamená připravenost transportu, **nikoli** dokončenou registraci pluginu nebo odebrání přístupu Aidy k Macu.

## Přepnutí Aidy

1. V OpenAI Platform → Tunnels vytvořit či zvolit soukromý tunel **Iris**, propojený pouze s Milošovým zamýšleným osobním ChatGPT workspace a jeho oprávněným účtem. Neaktivovat ho automaticky ve sdíleném firemním prostoru. Ověřit, kdo má Tunnels Use; nepoužívat širší sdílený tunel bez ověření autorizace. Přístup ke správě vyžaduje Read + Manage; provozní klíč Read + Use, žádný administrátorský klíč.
2. ID tunelu a jeho omezený provozní OpenAI klíč zadat **jen do aplikace Iris MCP**. Ne do chatu, CLI, souboru nebo prostředí zadaného agentovi. Kliknout „Uložit a spustit tunel“. Iris Connect musí běžet a mít povoleného nativního klienta.
3. V ChatGPT Plugins → Add custom MCP server zvolit **Tunnel**, stejný tunel a vytvořit soukromý plugin **Iris**. Privátní stdio spojení nemá veřejný endpoint ani vlastní webové přihlášení +4U. Oprávnění k tunelu a dostupnost pluginu se ověřují zvlášť. Nesdílet plugin dalším uživatelům; pokud účtové/workspace nastavení nedokáže omezit přístup na oprávněného uživatele, nepřepínat do běžného provozu.
4. Ověřit, že plugin nabízí přesně čtyři uvedené nástroje. Aidě explicitně zadat použití pluginu Iris pro `iris_get_access_status`, bez místní delegované úlohy. Ověřit výsledek od Aidy a pevný stav konektoru. Žádný `start` jen pro test.
5. V profilu Aidy **Computers → Your computer → Revoke access**. Tím se odebírá její obecné připojení k Macu, nikoli vývojářský přístup tohoto Codex projektu. Zkontrolovat také dřívější úlohy Aidy; revokace nemusí sama zastavit již běžící úlohy. Nedávat Aidě další obecný místní shell nebo souborové pluginy.
6. Odebrat Aidě dostupnost přímých +4U pluginů a přihlášených prohlížečových relací. Pouhé „vždy se ptej“ neznamená zákaz. Pokud platforma neumí omezit tyto cesty pro samotnou Aidu, hranice vyžaduje oddělený kontext účtu/workspace nebo vynucené řízení nástrojů; neodinstalovávat bez dalšího všechny uživatelovy +4U pluginy používané při jiné práci. Žádné skutečné přímé volání +4U pro test zákazu.
7. **Po revokaci** zopakovat `iris_get_access_status` přímo Aidou přes plugin Iris. Úspěšné volání s odpojeným Macem v profilu Aidy je hlavní akceptační důkaz. Poté samostatně ověřit upozornění a případný živý start na nový lidský pokyn.

Pokud není připravený tunel, osobní autorizovaný plugin nebo odebraná obecná oprávnění, přepnutí není dokončené. Současný stav nesmí být vydáván za úplnou síťovou izolaci celé platformy Dot: zákaz internetu je technicky ověřený v procesu tohoto MCP; běžící cloudové nástroje Aidy se spravují odděleně.

Oficiální dokumentace: [MCP server](https://developers.openai.com/plugins/build/mcp-server), [Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels), [připojení pluginu](https://developers.openai.com/plugins/deploy/connect-chatgpt), [přístup Aidy k počítači](https://learn.chatgpt.com/docs/dots/computers-and-apps).

## Automatické spuštění na Mini – host 0.2.0

Dva uživatelské GUI LaunchAgenty spravuje výhradně `python3 tools/deployment/mac-mini-startup.py install|status|remove` přímo z cílového projektu pod `irisagent`. Instalace odmítne jiný účet/cíl, běžící aplikace, neplatný podpis, cizí definici či symlink místo svého souboru. Nedefinuje systémový daemon ani tajné EnvironmentVariables; stdout/stderr míří do `/dev/null`. Start proběhne po vzniku Aqua relace, po normálním ukončení se aplikace nevnucuje zpět; havárie se obnovuje s omezením frekvence.

Host 0.2.0 má samostatnou místní volbu „Připojit tunel automaticky po spuštění aplikace“. Při automatickém startu se provozní klíč čte pouze nativně, s neinteraktivním LAContext; potřeba odemčení/souhlasu skončí pevným kódem bez opakování a bez nového ukládání klíče. Ruční tlačítko dovolí člověku schválit systémový přístup. Tunel se po selhání procesu sám ve smyčce nezahajuje. Spuštění transportu nikdy nezahajuje +4U login/MFA.

Iris Connect 0.5.0 umí na místní souhlas obnovit párování přesných podpisů aplikace a IrisControl; staré přihlašovací pokyny se nepřenášejí. První nastavení se provádí pouze lidsky v nativních oknech, bez jejich čtení agentem. Skutečné obnovení po ukončení aplikací a po restartu Mini se dokládá samostatně v [záznamu nasazení](../../docs/mac-mini-deployment.md).

## Návrh bezpečné rotace 30denního klíče tunelu

Miloš upozornil na 30denní expiraci provozního klíče. Následující je návrh navazující implementace, nikoli již zavedená rotace. Rozpracovaný test spouštění po restartu tím není zrušen a aplikace se během lidského nastavení nepřepisují. Přesný čas expirace nelze odvozovat jen z řetězce klíče nebo z dnešní instalace; převezme se jako ne-tajné metadata z Platform.

- Provozní klíč zůstane omezený na Tunnels Read + Use. Aida ani MCP nedostanou jeho hodnotu, administrátorský klíč nebo oprávnění vystavovat další klíče. Automatické klikání do účtu Platform není součástí návrhu.
- Pro první verzi člověk vytvoří náhradu před expirací a vloží ji pouze do nativního soukromého pole Iris MCP. Native uloží kandidáta do druhého vlastního Keychain slotu se stejnou ochranou podepsané aplikace; platný klíč se nepřepíše před ověřením. Žádný souborový fallback, export nebo zpřístupnění hodnoty přes MCP.
- Krátce se překryje platnost klíčů, nikdy dva současné stdio klienty stejného tunelu. Nejprve skončí původní klient, pak se spustí jeden klient s kandidátem. Po readiness se provede skutečné neautentizační volání iris_get_access_status přes plugin. Samotná readiness není důkazem celého průchodu. Rotace nesmí vyvolat MFA ani přerušovat již probíhající login.
- Při neúspěchu se kandidátní klient ukončí a lze se vrátit k dosud platnému původnímu klíči. Pokud původní už vypršel nebo byl zrušen, žádný fallback neexistuje; zobrazí se pevný stav vyžadující místní výměnu. Po ověřeném přepnutí člověk starý klíč zneplatní na Platform a aplikace pak odstraní jeho záložní Keychain kopii.
- Upozornění navrhnout 7, 3 a 1 den před expirací. Aida potřebuje pouze datum a stav. Cloudová připomínka musí být naplánovaná nezávisle na tunelu, aby se upozornění nemuselo poprvé získávat přes již expirovaný klíč. Lokální host může doplnit vlastní stavové upozornění. Nyní nebyla založená žádná automatizace ani rozšířené MCP schéma/sandbox; současné čtyři nástroje metadata transportního klíče nevracejí.

Současný host nemá kandidátní slot ani transakční výměnu. Jeho start při běžícím workeru nic neprovede; po zastavení se nový zadaný klíč ukládá před ověřením spojení. Tento ruční postup proto není vydáván za implementovanou bezpečnou rotaci s návratem. Plně automatické vystavování nebo workload identity se posoudí zvlášť až při ověřené podpoře pro tento konkrétní tunnel-client a účet; obecná podpora WIF není důkazem kompatibility tunelu.

Zdroje ověřené 18. října 2026: [OpenAI key safety – náhrada před expirací, test a následná revokace](https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety), [oprávnění runtime Secure MCP Tunnel](https://developers.openai.com/api/docs/guides/secure-mcp-tunnels).
