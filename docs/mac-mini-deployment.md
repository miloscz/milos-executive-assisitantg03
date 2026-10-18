# Iris Connect a MCP na Macu mini

Stav k 18. říjnu 2026. Miloš schválil přechod od místního prototypu k přípravě Macu mini. Vývojový Mac zůstává vývojový; původní Iris se nemění ani nevypíná.

## Ověřené připojení a předpoklady

- Účet `irisagent`, místní host `Iris--Mac-mini.local`, aktuální ověřená VPN adresa **100.64.80.102**. Původně uvedená `100.65.80.102` byla nesprávná; později byl nedostupný i překlad místního názvu. Na opravené VPN adrese se potvrdil tentýž lidsky ověřený SSH klíč.
- Miloš přímo na Macu mini potvrdil veřejný ED25519 otisk `SHA256:ptE142hvfEaI3DDT32H6qBIQ82hKh20apkfpKqXTA6k`. Instalační spojení používá právě tento připnutý veřejný klíč.
- Přihlášení k SSH provedl Miloš soukromě v Terminálu. Dočasné administrátorské spojení má vlastní socket v soukromé složce `build/mac-mini-ssh`; první spojení mělo nečinný limit 30 minut. Obnovené spojení přes VPN používá krátký socket `build/mac-mini-ssh/c`, limit dvě hodiny nečinnosti a kontrolu dostupnosti. Delší název `control-vpn` překročil při tvorbě dočasného socketu limit macOS; nepoužívat ho. Heslo se nezapisuje do projektu ani chatu. Toto spojení nesmí být připojené k Aidě.
- Čtecí kontrola hostu: macOS 27.0.1, arm64, GUI relace účtu irisagent, Swift 6.1.2, Node 24.15.0, Codex nainstalovaný, uspávání počítače nastavené na 0. [Kontrolní skript](../tools/deployment/mac-mini-preflight.sh) nevypisuje klíčenku, prostředí, konfigurace ani logy.

## Rozložení a instalace

Cílové zdroje: `/Users/irisagent/Personal/milos-executive-assisitantg03`. Obě podepsané aplikace zůstávají v `build/` tohoto projektu, protože host tunelu i MCP odvozují pevné cesty od této struktury. Konkrétní zdroje se přenášejí podle seznamu; žádná celá domácí složka, `.git`, `.env`, původní autentizační adresáře, Keychain, tokeny, místní pracovní data ani logy.

1. Přenést prověřené zdroje, schválenou read politiku a ověřený veřejný tunnel-client pro arm64.
2. Na cíli nainstalovat závislosti podle package-lock, bez instalačních skriptů. Nasadit obě aplikace s hardened runtime; ověřit podpisy a syntetické testy. Nepřepisovat běžící bundle. Aktuální toolchain Macu mini má nesoulad modulu a knihovny PackageDescription (neplatný manifest, následně chybějící symboly linkeru). Proto byly aplikace sestavené na vývojovém Macu pro arm64 s minimem macOS 14 a přenesené jako podepsané buildy. Systémové nástroje cíle se neměnily. Do opravy toolchainu se buildy vytvářejí na vývojovém Macu.
3. Otevřít Iris Connect v existující GUI relaci. Konfiguraci původního přihlašovacího klienta převzít pouze nativní volbou souboru `oidc.js`; aplikace parsuje pevné literálové konstanty, nikdy nespouští JavaScript, neukazuje hodnoty a ukládá je do vlastní klíčenky. Tato konfigurace není AC1/AC2 ani uživatelský token. Agent její hodnotu nesmí číst ani přidávat do repozitáře. Na vývojovém Macu zůstává kompatibilní interní načtení původního souboru při prvním přihlášení.
4. Miloš zadá AC1 a AC2 přímo v nativním okně na cíli, ověří přihlášení s telefonem a povolí IrisControl. Read klient a vlastní prostor mají samostatné párování. Nový build může vyžadovat nový místní souhlas klíčenky.
5. V Iris MCP Miloš zadá ID soukromého tunelu a jeho provozní klíč. Host uloží klíč do své vlastní klíčenky. MCP server ho nedostává. Ověřit readiness, poté skutečnou registraci a nástroje Aidy.
6. Odebrat Aidě obecné připojení k oběma Macům a ostatní přímé +4U cesty. Po odebrání znovu ověřit skutečné volání omezeného MCP. Zákaz v instrukcích sám nedokazuje síťovou izolaci celé platformy Dot.

Launcher MCP podporuje pevně vybrané instalace Node v `/opt/homebrew/bin/node` a `/usr/local/bin/node`. Žádný klientem zadaný spustitelný soubor. macOS sandbox zůstává povinný a omezuje MCP na přibalený IrisControl a jediný `auth.sock`.

## Zamčená obrazovka

### Ruční správa přes vzdálenou plochu

Miloš používá Sdílení obrazovky / vzdálenou plochu. První buildy měly na všech oknech `NSWindow.SharingType.none`; uživatel hlásil běžící aplikace bez viditelných oken. Iris Connect **0.4.1** a Iris MCP **0.1.1** používají `.readOnly`, aby mohl člověk okna zobrazit a spravovat vzdáleně. Také přístupové pole AC nyní výslovně potlačuje accessibility selected text vedle samotné hodnoty. Nativní okna jsou znovu otevřená a podpisy obou celých bundle ověřené. Miloš následně potvrdil, že ve vzdálené ploše vidí obě okna.

Maskování NSSecureTextField, soukromé AX hodnoty, klíčenka, zákaz čtení přihlašovacího UI agentem a úzké MCP zůstávají zachované. Legacy příznak sdílení okna není bezpečnostní hranicí vůči agentům ani zárukou proti všem metodám zachycení obrazovky; [Apple ho popisuje jako starší konstantu](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum). Přístup ke vzdálené ploše má člověk; Aidě se žádné obecné ovládání Macu mini nepřipojuje.

### Přihlášení na pozadí

Zdrojová verze Iris Connect 0.4.0 přidává výslovné místní nastavení „Povolit přihlášení přes MCP při zamčené obrazovce“, standardně vypnuté. Měnit jej lze pouze v odemčené aplikaci bez běžícího pokusu. Zamčení není uspání, odhlášení ani restart.

- V povoleném režimu zůstane spárované omezené ovládání dostupné. Aida připraví požadavek, skutečně upozorní Miloše a teprve po novém přímém pokynu spustí jediný pokus. Zůstávají jednorázová noticeID/requestID, časové limity a zákaz automatických opakování.
- Nativní aplikace použije klíčenku bez interakce při zamčení. Pokud Keychain vyžaduje odemčení nebo nový souhlas, pokus skončí; aplikace neodemkne macOS, neukládá heslo k účtu a nesnižuje ACL položek. Stávající file-based Keychain se nemění na synchronizovanou klíčenku.
- Ruční přihlášení z místního okna se při zamčení ruší. Pouze pokus zahájený přes spárované ovládání smí pokračovat v povoleném režimu. Citlivý vstupní panel se při zamčení zavře.
- Aplikace drží omezenou procesní aktivitu pouze po dobu přihlašovacího pokusu. WebKit při zamčení a dostupnost klíčenky musí být ověřené na skutečném Macu mini; syntetické testy to nedokazují.
- Detekce zámku využívá systémové signály, jejichž lock klíč/oznámení nejsou stabilním dokumentovaným kontraktem. Neznámý počáteční stav se považuje za zamčený; pro prvotní nastavení jednou zamknout a odemknout. Chování musí projít kontrolou na cílovém systému.
- `verification.json` obsahuje pouze validované příznaky `screenLocked`, `backgroundLoginEnabled` a `backgroundAttempt`. Poslední z nich znamená pokus zahájený přes MCP již při zamčené obrazovce a přetrvá i po ukončení pokusu. Obsah se čte výhradně validujícím status helperem.

První přihlášení uživatele po restartu/FileVault, případné odemčení klíčenky a nové párování po restartu aplikace zůstávají místními kroky člověka. Aktuální párování helperů platí pouze pro běh aplikace a host tunelu se spouští místním tlačítkem. Automatický trvalý start po restartu zatím není hotový. Iris Connect potřebuje GUI relaci; systémový LaunchDaemon pod rootem ji nenahradí. FileVault, zámek obrazovky ani ochrana klíčenky se nevypínají.

## Přijímací ověření

1. Nejprve člověkem potvrzený živý průchod v odemčené aplikaci: automatická volba Plus4U Access, MFA a úspěšné čtení.
2. Ověřit MCP status, připravení a doručení upozornění bez spuštění MFA.
3. Zapnout místní background nastavení, zamknout Mac mini a potvrdit přes MCP `locked=true` a `backgroundLoginEnabled=true`.
4. Po novém upozornění nový přímý Milošův pokyn; potvrdit MFA pouze telefonem. Bez snímků, AX, DOM nebo jiného čtení přihlašovacího okna agentem.
5. Ověřit stav podpisu tokenu a čtení pouze přes sanitizované rozhraní; Miloš samostatně potvrdí MFA. Zaznamenat výsledek a limity.
6. Záporné scénáře: bez místního povolení start při zamčení neprojde; staré upozornění neprojde; stejné requestID nezpůsobí druhý pokus; restart nic sám nespustí; vyžadovaný místní souhlas klíčenky nesmí vést k opakování nebo souborovému fallbacku.

Dosavadní výsledek: vybrané zdroje a ověřený tunnel-client 0.0.16 byly přenesené na Mac mini s kontrolou SHA-256 jednotlivých souborů. Závislosti jsou nainstalované podle lockfile bez instalačních skriptů. Podepsané Iris Connect 0.4.1 a Iris MCP 0.1.1 jsou nasazené, oba celé bundle prošly `codesign --verify --deep --strict`. Sanitizované stavy před výměnou buildu potvrzovaly Connect `ready` bez tokenu a host tunelu `stopped`; běžící Connect zachytil odemčení. Miloš potvrdil viditelnost obou oken ve vzdálené ploše. Kódy, tokeny ani stará konfigurace nebyly do instalačního balíčku přenesené.

34 syntetických Swift testů a 12 testů omezeného MCP prošlo na vývojovém Macu; dalších 12 MCP testů včetně skutečných OS zákazů sítě, souborů a procesů prošlo také přímo na Macu mini. Nejde o důkaz živého přihlášení při zamčení na cíli. První ruční přihlášení a čtení identity na Macu mini prošlo; soukromý tunel, připojení Aidy, revokace jejího starého obecného přístupu a živý test při zamčení ještě čekají. Mac mini nebyl připojený k Aidě jako obecný počítač.

Související platformní dokumentace: [uživatelské SSH připojení Codex](https://learn.chatgpt.com/docs/remote-connections), [neinteraktivní autentizační kontext klíčenky](https://developer.apple.com/documentation/security/ksecuseauthenticationcontext), [omezení atributu dostupnosti Keychain na macOS](https://developer.apple.com/documentation/security/ksecattraccessible). Tato dokumentace sama nepotvrzuje živý průchod +4U ve WebKitu při zamčení.

## Převzetí konfigurace klienta – dokončeno

Miloš výslovně schválil přesný jednorázový přenos původního zdrojového `iris-dwg-mcp/src/oidc.js`, který obsahuje klientské tajemství, na ověřený Mac mini do `/Users/irisagent/.iris-client-import/oidc.js`. Přenos následně prošel. Obsah souboru nebyl vypsán ani uložen do repozitáře. Soukromý adresář měl práva 0700 a soubor 0600. Miloš potvrdil úspěšný nativní import do klíčenky Iris Connect. Poté byla přesně tato dočasná kopie odstraněna a prázdná složka zrušena; agent její obsah nečetl. Převzetí do klíčenky je doložené uživatelským potvrzením, nikoli čtením položky agentem. Původní zdroj zůstává nedotčený. AC1/AC2, tokeny, `.env`, jiné credential soubory ani klíčenka nebyly součástí přenosu.

Původní pokus automatická bezpečnostní kontrola odmítla pro chybějící konkrétní schválení citlivého payloadu a cíle; přenos proběhl teprve po výslovné lidské odpovědi. Schválení se vztahuje pouze na tento import, nikoli na obecný přenos tajných údajů.

Následuje první živé přihlášení přímo na Macu mini: Miloš zadá AC1/AC2 výhradně v nativní aplikaci a sám spustí přihlášení, MFA potvrdí telefonem. Agent nesnímá ani neovládá přihlašovací okna; ověřuje pouze sanitizované stavy. Miloš následně potvrdil, že přihlášení a čtení identity jsou ověřené; agent to doložil pouze sanitizovaným stavem.

## První živé přihlášení na Macu mini

18. října 2026 ve 14:55:39 Europe/Prague sanitizovaný stav potvrdil `authenticated`, `tokenSignatureVerified=true`, `readProbePassed=true`, `credentialsSubmittedByApp=true` a `accessMethodSelectedByApp=true`, bez validačních chyb. Miloš v konverzaci potvrdil úspěšné přihlášení a čtení identity. Nebylo čtené UI, token, kódy ani položka klíčenky. Native `mfaConfirmedByUser=false` znamená, že nebylo stisknuté volitelné diagnostické tlačítko; Miloš následně výslovně potvrdil dokončení MFA na telefonu v konverzaci. To nemění volitelný příznak nativního tlačítka. Token měl v okamžiku kontroly uvedenou platnost do 15:25:39 Europe/Prague; tento záznam sám nepotvrzuje aktuální platnost později.

Přihlášení proběhlo odemčené, `backgroundLoginEnabled=false`, `backgroundAttempt=false`. Čtecí klient ještě nebyl spárovaný, seznamy úkolů/kalendáře se na cíli dosud neověřily a host tunelu hlásil `stopped`. Následuje místní povolení IrisControl, background opt-in, potvrzení vlastního prostoru a diagnostické čtení. Tyto kroky nepřipojují Mac mini jako obecný počítač Aidy a samy nevyvolají další MFA.

## Potvrzení čtení a příprava soukromého tunelu

Miloš následně výslovně potvrdil, že pracovní čtení prošlo, místní ovládání i background nastavení jsou zapnuté a MFA dokončil na telefonu. Tento výsledek je v této fázi doložený jeho odpovědí. Navazující nezávislá kontrola sanitizovaných počtů a read-only MCP smoke nemohla proběhnout: SSH master ztratil spojení, místní jméno Macu mini se nepřeložilo a zkouška původní VPN adresy skončila timeoutem. Nebyly získané výsledky smoke ani počty seznamů; nelze je vydávat za ověřené agentem. Nebyl spuštěný nový login ani MFA.

S funkční vzdálenou plochou může Miloš pokračovat přímo v nativním Iris MCP: soukromý tunel Iris asociovaný se zamýšleným osobním ChatGPT workspace a omezený runtime klíč Tunnels Read + Use. Obě hodnoty zadává výhradně do aplikace. Připravenost transportu, skutečná registrace pluginu, úspěšné čtyři řídicí nástroje a revokace obecného přístupu Aidy zůstávají samostatné následující kontroly. Obnovení administrátorského SSH není náhradou tohoto spojení a Aidě se neposkytuje.

## Obnovená kontrola pracovního čtení a MCP

Po obnovení SSH přes správnou VPN adresu byly nezávisle přečtené sanitizované výsledky pilotu: `calendar.list` 302 záznamů / 2 strany, `tasks.listActive` 2 183 záznamů / 11 stran a `tasks.listFinal` 343 záznamů / 2 strany. Všechna čtení uspěla. Aktivní záznamy mají ověřený kontrakt a dokončené stránkování; kalendář a finální záznamy zůstávají `contractPending`, nejsou deklarované jako úplná provozní synchronizace.

Read-only MCP smoke přímo na Macu mini úspěšně inicializoval SDK, ověřil přesný seznam čtyř řídicích nástrojů a získal `ok=true`, `enabled=true`, `backgroundLoginEnabled=true`, `locked=false`, `busy=false` a v okamžiku kontroly `sessionValid=true`. Nevolal prepare, noticeSent ani start. Žádné nové MFA nevyvolal. Toto potvrzuje místní spojení, nikoli spojení Aidy přes tunel.

## Diagnostika spuštění hostu tunelu 0.1.2

Miloš nahlásil původní obecnou chybu „Tunel nelze spustit. Ověř klíč, klíčenku a místní instalaci.“ Sanitizovaný stav byl `failed/running=false/ready=false`. Metadata potvrdila správnou cestu běžícího hostu, existenci spustitelného launcheru i tunnel-client, dostupnost Node, zapisovatelnou složku aplikace a platný podpis. Klíč, jeho klíčenka, transport.yaml, prostředí, UI a transportní logy se nečetly.

Nasazený Iris MCP **0.1.2** nyní odlišuje pevné kódy validace, kontroly podpisu, chybějícího klíče, jednotlivých kategorií Keychain, instalace, zápisu nastavení a spuštění/ukončení procesu. Žádné chybové texty z OS ani síťové odpovědi se do diagnostiky nepřebírají. Kontroly instalace předcházejí přístupu ke klíči. Validní ne-tajné ID se zachová i po neúspěšném startu; API klíč se takto neukládá.

Sanitizovaný receipt verze 2 přidává pouze pevný enum `failure`; validátor stále přijímá starší verzi 1, odmítá neznámé hodnoty/pole a rozporný stav připravenosti. Prošlo devět syntetických skupin Swift policy testů a pět testů Python validátoru; těchto pět testů prošlo i na cíli. Podepsaný host byl před nahrazením řádně ukončený, celý bundle znovu ověřený a otevřený. Iris Connect se nerestartoval. Tunel ani +4U login nebyly spuštěné agentem. Čeká se na uživatelské opakování místního startu a pevný chybový kód nebo připravenost.


## Formát uloženého provozního klíče – host 0.1.3

Sanitizovaný stav po lidském startu verze 0.1.2 vrátil `failed`, `running=false`, `ready=false`, `failure=storedKeyInvalid`. Tím se problém omezil na nativní kontrolu uložené hodnoty; agent žádnou hodnotu nečetl. ID tunelu sdělené Milošem odpovídalo očekávanému tvaru.

Původní regex s `$` připouštěl koncový newline; nová striktní validace jej odmítá. Host **0.1.3** před validací interně odstraní pouze okolní whitespace při zadání i při použití uloženého klíče. Neodstraňuje mezery nebo jiné znaky uvnitř, nemění jiné neplatné hodnoty a nepublikuje původní ani normalizovanou hodnotu. Čtení staré položky kvůli tomu nepřepisuje klíčenku. Na skutečnou příčinu původního nesprávného formátu se bez hodnoty neusuzuje; ověření probíhá dalším lidským startem.

Prošlo deset syntetických skupin včetně LF/CRLF/tab/okolních mezer a odmítnutí vnitřního whitespace i záměny klíče za ID. Verze 0.1.3 je podepsaná, nasazená a otevřená po řádném ukončení předchozího hostu. Agent neprovedl žádný automatický start tunelu nebo MFA. Čeká se na nový stav z nativní aplikace.

## Oprava generovaného YAML – host 0.1.4

Po lidském startu verze 0.1.3 aplikace i validovaný receipt hlásily `clientExited`. To dokládá spuštění a následné ukončení procesu, nikoli úspěšnou autentizaci k OpenAI. Syntetická reprodukce se stejným tvarem konfigurace odhalila konkrétní chybu: Swift JSONEncoder standardně zapisoval lomítka jako `\/`, což YAML parser klienta 0.0.16 odmítá jako neznámou escape sekvenci. Provozní konfigurace, klíč, prostředí, klíčenka, UI ani logy nebyly čtené.

Host 0.1.4 používá `withoutEscapingSlashes`; ostatní escapování řetězců zůstává zachované. Regresní integrační test generuje YAML přímo produkčním Swift kódem, použije pouze smyšlené vstupy, dočasný HOME a loopback control-plane URL. Oficiální `tunnel-client doctor` opravený zápis přijal a původní variantu odmítl při `profile_load`. Prošlo také 11 syntetických skupin Swift policy testů a sestavení s kontrolou celého podepsaného bundle. Živé spojení stále vyžaduje nový místní start uživatelem; MFA se tím nespouští.

Verze 0.1.4 je nasazená a otevřená na Macu mini. Předchozí host byl řádně ukončený a nový bundle prošel `codesign --verify --deep --strict`. Sanitizovaný stav po otevření je `stopped`, `running=false`, `ready=false`, `failure=none`. Iris Connect se nerestartoval. Čeká se na lidský místní start a ověření transportu; soukromý plugin a přepnutí Aidy zatím dokončené nejsou.

Po místním startu Miloš potvrdil připravenost tunelu; nezávislý validovaný stav ji doložil jako `ready`, `running=true`, `ready=true`, `failure=none` dne 18. října 2026 v 16:12:15 Europe/Prague. To potvrzuje transportní readiness, nikoli připojení Aidy nebo úspěšné volání přes soukromý plugin. MFA se nespouštělo. Miloš současně oznámil upozornění macOS na malware s názvem Codex; přesný text a postižená komponenta se teprve ověřují. Do vyjasnění nepokračujeme připojením Aidy a nevypínáme systémovou ochranu.

Kontrola pouze instalačních artefaktů na Macu mini našla `/Applications/ChatGPT.app` verze 26.1013.40934, bundle ID `com.openai.codex`, tým `2DC432GLL2`. Celý bundle prošel `codesign --verify --deep --strict` a `spctl` jej přijal jako `Notarized Developer ID`. Stejné systémové schválení získal přibalený nativní Codex CLI a Codex Computer Use.app. Samostatný launcher `codex-cli/bin/codex` nemá vlastní podpis; jeho samostatné posouzení proto neprošlo, zatímco celková pečeť bundle prošla. To samo nedokládá malware ani nevysvětluje oznámení uživatele. Nebyl spuštěn žádný prověřovaný program, čtené uživatelské logy nebo měněná ochrana systému. Přesný text hlášení a počítač, kde vzniklo, stále chybí; výsledek těchto kontrol není tvrzením o úplné bezpečnosti zařízení.

Miloš původní upozornění zavřel a přesný text nemá; při opakování jej sdělí. Systémová ochrana zůstává zapnutá a příčina varování není prohlášena za vyřešenou nebo falešný poplach. Bez spouštění zablokované položky pokračuje příprava soukromého pluginu nad již běžícím tunelem. Vyhledávání pluginů nenašlo odpovídající instalovaný Iris; to není úplný inventář soukromých připojení. Registraci proto provede Miloš ve svém osobním workspace přes Plugins → Add custom MCP server → Tunnel, poté se ověří skutečná dostupnost čtyř nástrojů.

## Živý průchod registrovaným pluginem

18. října 2026 přibližně v 16:30 Europe/Prague uspělo přímo z implementačního chatu volání `iris_get_access_status` přes skutečně registrovaný soukromý plugin **Iris Tunel**. Nativní odpověď potvrdila `ok=true`, `enabled=true`, `locked=true`, `backgroundLoginEnabled=true`, `credentialEntryRequired=false`, `busy=false`, `sessionValid=false`, fázi `idle` a žádnou čekající práci. Tím je prokázaný celý průchod plugin → tunel → sandboxovaný MCP → podepsaný IrisControl → Iris Connect bez obecného připojení počítače pro toto volání. Nejde o přihlášení při zamčení; žádný start/MFA nebyl vyvolaný. Čtyři očekávané nástroje jsou dostupné, ale hlavní Aida zatím nereaguje a její vlastní volání ani revokace obecného přístupu nejsou potvrzené. Podrobnosti a následující kroky jsou v integrations/aida/README.md.

2026-10-18T16:36:25+02:00: Miloš potvrdil odebrání obecného přístupu Aidy k Macu. Následující volání stavu přes Iris Tunel z implementačního chatu znovu uspělo (`ok=true`, zamčeno, background opt-in zapnutý, login neběží, relace neplatná). Revokace je uživatelské potvrzení, nikoli přímo přečtené nastavení. Vlastní volání hlavní Aidou není doložené, protože nereaguje a podle Miloše v její Activity nepřibyla činnost od poledne. Diagnostika pokračuje zkouškou stejné Aidy na telefonu. Žádný start/MFA se neprovedl.

2026-10-18T16:37:31+02:00: Miloš následně předal odpověď hlavní Aidy potvrzující použití `iris_get_access_status` přes plugin Iris. Výsledek odpovídá přímým testům: spojení funguje, Mac je zamčený, background opt-in je zapnutý, relace vypršela a přihlášení neběží. Aida výslovně uvedla, že login/MFA nespustila. Spolu s potvrzenou revokací jde o dokončenou zkoušku přepnutí na soukromý plugin; důkaz vlastní Aidiny odpovědi je uživatelské předání, nikoli přímo přečtená interní historie. Živý MFA průchod při zamčení a kontrola dalších přímých +4U cest zůstávají odděleně nedokončené.

2026-10-18T16:39:29+02:00: v navazující zkoušce Miloš předal upozornění hlavní Aidy před MFA. Přímý stav pluginu potvrdil `awaitingUser`, `workPending=true`, `busy=false`, zamčený Mac, povolený background režim a upozornění platné do 16:49:04 Europe/Prague. Odeslání je nativně zaznamenané; nový lidský pokyn ke startu ještě nezazněl. Implementační chat volal pouze status.

## Živý MFA průchod při zamčeném Macu mini – úspěšný

18. října 2026 v 16:40:50 Europe/Prague přímé volání `iris_get_access_status` přes Iris Tunel potvrdilo `ok=true`, `enabled=true`, `sessionValid=true`, `phase=authenticated`, `busy=false`, `locked=true`, `backgroundLoginEnabled=true`, `credentialEntryRequired=false` a `workPending=false`. Stav obsahoval identifikátor přihlašovacího požadavku; předchozí kontrola po upozornění byla `awaitingUser` při `locked=true` a bez běžícího pokusu. Miloš výslovně potvrdil, že MFA přišlo a schválil ho na telefonu.

Akceptační výsledek: upozornění skutečně předala hlavní Aida, nativní konektor zaznamenal jeho odeslání, po navazujícím lidském pokynu přišlo MFA, člověk ho potvrdil a nativní stav následně hlásí platnou přihlášenou relaci při zamčeném Macu. Obecný přístup Aidy k Macu byl před touto zkouškou podle Milošova potvrzení odebraný. V implementačním chatu se volal jen status, nikoli prepare, confirm nebo start; nebylo provedeno čtení UI, klíčenky, tokenu nebo přístupových kódů.

Důkaz tvoří přímý nativní stav přes omezený plugin a lidská potvrzení doručeného upozornění, revokace a MFA. V tomto navazujícím kroku nebyl samostatně čten sanitizovaný autentizační receipt s příznaky podpisu tokenu/readProbePassed ani znovu proveden pracovní čtecí pilot; jeho předchozí úspěch je zaznamenaný odděleně. Výsledek neprokazuje fungování po odhlášení, restartu, uspání, při zamčené klíčence vyžadující nový místní souhlas nebo automatický start aplikací. Kontrola jiných přímých +4U cest Aidy a starších úloh zůstává samostatná.

## Automatické spuštění – implementace a výchozí stav

Nasazené jsou Iris Connect 0.5.0 a Iris MCP 0.2.0, ověřené celé podepsané bundle. Aplikace nyní běží přímo pod dvěma uživatelskými LaunchAgenty `net.iris.connect.login` a `net.iris.mcp-host.login` v Aqua relaci účtu irisagent. Instalaci a pevný stav spravuje `tools/deployment/mac-mini-startup.py`; záměrně nejsou používány systémové daemony, root nebo souborové klíče. Oba joby byly po bootstrap skutečně běžící. Zdroj hostu při prvním pokusu neprošel kompilací kvůli optional UI prvku; před místním nastavením byl opraven, sestaven a nahrazen ověřenou verzí 0.2.0.

Výchozí bezpečně zjištěné nastavení Mini: macOS 27.0.1, FileVault Off, existující `autoLoginUser=irisagent`, konzolový uživatel irisagent, původní `kern.boottime.sec=1792323220`. Agent FileVault ani automatické přihlášení nenastavoval a žádné heslo k macOS nečetl. Přihlášení OS je oddělené od MFA +4U. Bez Aqua relace uživatelské aplikace nenaběhnou.

Nová místní volba Connectu připíná souhlas k obnově řídicího párování na přesný hardened CDHash aplikace i helperu. Restart zneplatňuje upozornění a neobnovuje token ani nedokončené MFA. Nová místní volba MCP obnoví pouze transport; čtení jeho klíče při startu je neinteraktivní a případný souhlas člověka nesmí být obcházen. Nativní kontrola klíčenky v Connectu slouží k jednorázovému povolení nové verze bez síťového přihlášení/MFA.

Prošlo 33 syntetických Swift testů v aktuálním testovacím běhu, včetně shody obou podpisů, odmítnutí jiné verze/metadat a zneplatnění starého startu. Prošly dva testy bezpečného správce LaunchAgentů také na Mini, 11 skupin policy hostu a syntetická kontrola generovaného YAML oficiálním klientem. Žádný skutečný klíč/token neprošel testy ani výstupem agenta.

Čeká se na místní zapnutí obnovení párování, kontrolu klíčenky a zapnutí automatického připojení tunelu člověkem. Následuje kontrolované ukončení/nové spuštění aplikací přes stejné LaunchAgenty a teprve poté skutečný restart počítače s porovnáním bootTime. Úspěch bootstrap nebo restartu aplikací není důkazem restartu macOS. Čtecí párování vlastního prostoru, nový živý MFA pokyn a souhlasy po případné další změně podpisu zůstávají oddělené.

## Kontrolovaný restart aplikací – ověřeno

2026-10-18T17:47:34+02:00: Miloš potvrdil místní zapnutí obnovení párování a automatického připojení; Iris MCP hlásil připravenost. Přímé MCP volání před restartem potvrdilo nečinný konektor bez platné relace a bez čekající práce. Obě aplikace byly řádně ukončené, bylo ověřené ukončení tunnel-client a stejnými LaunchAgenty znovu spuštěné (kickstart bez násilného ukončení). PID Connectu se změnil 12053 → 12292 a hostu 11800 → 12295; bootTime zůstal 1792323220.

Host po obnovení sám přešel do `ready`, `failure=none`. Sanitizované ověření Connectu hlásilo `ready`, bez tokenové relace, credentialsSubmittedByApp=false, probe=notStarted a backgroundAttempt=false. První cloudové volání stavu po výměně procesů skončilo timeoutem; druhé úspěšně vrátilo `ok=true`, `enabled=true`, `sessionValid=false`, `busy=false`, `locked=true`, `backgroundLoginEnabled=true`, `credentialEntryRequired=false`, `phase=idle` a `workPending=false`. Párování i transport se tedy skutečně obnovily bez nového místního kliknutí a bez přihlášení/MFA. `locked=true` může po spuštění také vyjadřovat konzervativní neznámý stav zámku; tento krok není novým testem MFA při zamčení.

Samostatný pokus o lokální smoke použil neexistující /opt/homebrew/bin/node a neproběhl; není vydáván za další test. Přímo fungující cloudové MCP volání dokládá skutečný průchod přes používaný launcher, který podporuje i /usr/local/bin/node. Po úspěchu nebylo provedeno další zbytečné opakování.

Následuje lidsky provedený restart Mini přes nabídku Apple, bez ručního otevírání Iris aplikací. Zjišťuje se, zda stávající automatické přihlášení macOS skutečně obnoví Aqua relaci a zda při studeném startu nebude potřeba ruční odemčení/souhlas klíčenky. Skutečný reboot zatím není potvrzený.

## Restart macOS a nedostupná správní cesta

2026-10-18T17:54:06+02:00: Miloš potvrdil restart Mini a oznámil, že NordVPN na jeho vzdálené ploše požadovalo heslo k aktualizaci; od té chvíle se nedostane ke Sdílení obrazovky. Bez ručního otevření Iris aplikací následné skutečné volání přes Iris Tunel uspělo: `ok=true`, `enabled=true`, `sessionValid=false`, `busy=false`, `locked=true`, `backgroundLoginEnabled=true`, `credentialEntryRequired=false`, `phase=idle`, `workPending=false`, nové eventId. To prokazuje dostupnost obnoveného Connectu i tunelu po uživatelem potvrzeném restartu. Samostatný nový kern.boottime zatím nebyl přečten, protože správní spojení není dostupné. Login/MFA neproběhl.

První krátké TCP pokusy k 100.64.80.102 na 22/5900 uspěly, ale následné SSH a skutečné čtení veřejných SSH/RFB bannerů již skončily timeoutem; samotný TCP úspěch se nepovažuje za důkaz fungující služby. Místní název Iris--Mac-mini.local také není dostupný. Nově otevřené nativní Sdílení obrazovky na IP podle Miloše zůstává na Připojování. Route k ověřené VPN adrese na vývojovém Macu vede přes utun5. Na tomto Macu je NordVPN, jeho hlavní VPN služba je hlášená Disconnected; to samo nevypovídá o stavu Meshnet peeru.

Miloš nemá Mini ve stejné LAN a nemá u něj fyzický přístup. Vyžádán je pouze ne-tajný stav zařízení Mini a jeho aktuální Meshnet IP/Nord název v NordVPN na tomto Macu. K žádné změně VPN, firewallu, oprávnění zařízení, aktualizace nebo hesla nedošlo. Požadavek na administrátorské heslo se nepotvrzuje agentem. MCP zůstává čtyřnástrojové a nepřidává se záchranný shell ani ovládání síťových služeb. Příčina výpadku správy není doložená; souvislost s aktualizací je uživatelské pozorování.

Provozní závěr je zatím dílčí: automatické obnovení Iris je doložené, ale nelze prohlásit plně bezobslužný provoz Mini. NordVPN může při aktualizaci vyžadovat lidský souhlas a nezávislá dostupná správní cesta zatím není ověřená. Nejprve je nutné obnovit správní přístup a teprve poté ověřit nový bootTime a přesné ruční kroky po rebootu.

## Obnova spojení na vývojovém Macu – bez obnovení správy Mini

2026-10-18T17:59+02:00: uživatelský snímek i nativní Meshnet na vývojovém Macu ukazují Mini online na nezměněné adrese 100.64.80.102. Vzdálený přístup je povolený v obou směrech. Obnova místního Meshnet Off → On nezpřístupnila SSH ani Sdílení obrazovky. Hlavní VPN spojení v nativní aplikaci bylo Connected (New York, United States); dřívější výstup systémové služby Disconnected tedy není důkazem aktuálně odpojené VPN.

Po výslovném souhlasu Miloše byla přes nativní Reconnect jednorázově obnovena stávající hlavní VPN na vývojovém Macu. Aplikace nadále ukazuje zabezpečené spojení, ale následné ohraničené pokusy na porty 22 a 5900 opět neprošly ani navázáním TCP. Obnova nepomohla a příčina výpadku Mini zůstává neurčená. Oprávnění peerů, firewall, ochrany ani konfigurace Mini se neměnily.

Ve stejném kroku znovu uspělo skutečné `iris_get_access_status` přes Iris Tunel: enabled=true, sessionValid=false, busy=false, backgroundLoginEnabled=true, locked=true, credentialEntryRequired=false, phase=idle a workPending=false. Iris tedy zůstává přes omezený tunel dostupná. Agent nevyvolal login/MFA. Pro další správu se zjišťuje existence jiné již nastavené nezávislé vzdálené cesty; bez ní nebo místního zásahu zatím nelze pokračovat přes SSH.

Miloš potvrdil, že jiná vzdálená správní cesta nastavená není. Dosud zkoušená rozhraní správu neobnovila. Před případným místním zásahem se ale musí ověřit také nativní vzdálené spojení již nainstalovaného Codexu, viz další odstavec. Iris aplikace ani její klíče není potřeba kvůli výpadku znovu nastavovat; omezený MCP stále odpovídá.

## Možnost obnovy přes nativní vzdálené spojení Codexu

Na návrh Miloše se ověřuje možnost využít Codex na Mini pouze pro správu, odděleně od Aidy. [Oficiální dokumentace](https://learn.chatgpt.com/docs/remote-connections) popisuje zabezpečený relay pro již povolené a spárované desktopové hosty; tato cesta je odlišná od Codex SSH, které vyžaduje funkční SSH. Pouhá instalace aplikace vzdálené spojení nedokládá. Host musí být online, přihlášený do příslušného účtu/workspace a aplikace musí běžet.

Seznam projektů z implementačního chatu zatím nabízí pouze místní projekty, žádný projekt Mini; není to úplný důkaz stavu párování v nastavení Connections. Pokus o kontrolu nastavení přes Computer Use nástroj byl z bezpečnostních důvodů zablokovaný pro aplikaci com.openai.codex. Kontrolu Settings → Connections → Control other devices proto provede uživatel. Nové párování, oprávnění ani zpráva jiné úloze nebyly provedené. Aida zůstává bez obecného přístupu k počítači, pouze s omezeným MCP. Předchozí kategorický závěr o nutnosti místního zásahu byl předčasný; tato samostatná cesta ještě není ověřená.

Miloš následně potvrdil, že Mini v seznamu Control other devices tohoto Macu není. Tato přímá cesta zde tedy není připravená. Zbývá ověřit případné samostatné dřívější spárování mobilní aplikace ChatGPT s Mini; párování je specifické pro ovládající zařízení. Pokud ani takové spojení neexistuje, samotná instalace Codexu na Mini správu na dálku neumožní a jeho první povolení bude vyžadovat přístup k hostu. Žádná oprávnění Aidy se nemění.

## Návrat k místnímu provozu na pokyn Miloše

18. října 2026 přibližně v 18:05 Europe/Prague Miloš rozhodl nejprve rozjet provoz na tomto Macu a přenos na Mini dokončit později. Původní Mini se vzdáleně nevypíná a jeho tunel nelze považovat za zastavený. Zde se proto připravuje jiné soukromé ID tunelu a plugin Iris Local. Tajné hodnoty ani klíčenky se mezi hosty nekopírují.

Oba existující místní bundle (Connect 0.5.0, MCP 0.2.0) prošly `codesign --verify --deep --strict`; aplikace před spuštěním neběžely. Nebyl proveden nový build ani změna podpisu. Místní preference autoConnectTunnel nebyla nastavená, takže host při spuštění sám tunel nezahájil. Instalační helper nyní podporuje explicitní pevný cíl current-mac vedle výchozího mac-mini; ostatní účty a cesty odmítá. Kontrola běžících aplikací při chybě systémového výpisu končí bezpečně. Prošly tři syntetické testy helperu a všech 12 testů MCP včetně OS zákazu sítě, nepovolených souborů a programů.

Instalace obou místních LaunchAgentů uspěla: Connect PID 86104, host PID 86107, bootTime tohoto vývojového Macu 1791559063. Sanitizovaný stav Connectu je ready bez podepsané relace, bez odeslání kódů a bez MFA. Host je stopped, failure=none. Read-only MCP smoke potvrdil přesně čtyři nástroje a unavailable před místním povolením párování člověkem. Předchozí příkaz s neexistujícím /opt/homebrew/bin/node neproběhl; skutečný smoke byl proveden dostupným node a používal produkční launcher. Agent nečetl přihlašovací UI, Keychain hodnoty ani konfiguraci tunelu.

Čeká se na místní převzetí klientské konfigurace, kontrolu přístupu podepsané aplikace ke klíčence a povolení ovládání/obnovy párování uživatelem. Přihlášení zatím nesmí být automaticky vyvolané. Stav soukromého pluginu Iris Tunel se nesmí vydávat za stav tohoto Macu — dosud obsluhuje Mini.

Miloš následně potvrdil dokončení místních kroků. Skutečný read-only smoke produkčního místního MCP potvrdil přesně čtyři nástroje a stav ok=true, enabled=true, sessionValid=false, busy=false, backgroundLoginEnabled=true, locked=false, credentialEntryRequired=false, phase=idle, workPending=true. Nešlo o volání cloudového pluginu Mini. Zaznamenaná čekající potřeba přístupu není souhlasem ke startu; implementační chat volal pouze status. Host tunelu je nadále stopped, failure=none. Následuje lidské vytvoření samostatného soukromého tunelu Iris Local a zadání jeho provozního klíče pouze do nativní aplikace.

18. října 2026 v 18:10 Europe/Prague Miloš potvrdil připravenost nového místního tunelu. Sanitizovaný aktuální receipt nezávisle potvrdil stage=ready, running=true, ready=true, failure=none. Místní read-only MCP smoke opět uspěl se stejnými čtyřmi nástroji, enabled=true, sessionValid=false, busy=false, backgroundLoginEnabled=true, locked=false a credentialEntryRequired=false. Hodnota klíče, ID ani konfigurace nebyly čtené. V katalogu implementačního chatu je dosud pouze původní plugin Iris Tunel, nikoli Iris Local. Nový plugin a přepnutí hlavní Aidy zůstávají dalším krokem. Přihlášení/MFA se nevyvolalo.

Miloš následně potvrdil vytvoření pluginu Iris Local a viditelnost všech čtyř očekávaných nástrojů. Katalog callable nástrojů tohoto implementačního chatu však stále nabízí jen Iris Tunel; žádný nástroj Iris Local zatím není dostupný. Vyhledávání pluginů nový soukromý plugin nevrátilo; jeho výsledky nejsou úplným inventářem a nejsou důkazem neúspěšného vytvoření. Uživatel má zpřístupnit Iris Local tomuto chatu, aby šlo provést skutečné stavové volání před přepnutím Aidy. Starý plugin nebyl použit jako náhrada testu nového hostu. Žádné MFA ani změna oprávnění se neprovedly.

Po explicitním připojení Iris Local uživatelem jsou v implementačním chatu dostupné přesně čtyři očekávané nástroje tohoto nového pluginu. Přímé `iris_get_access_status` přes Iris Local živě uspělo. Souběžné místní read-only MCP volání vrátilo stejný eventId i stejné pevné příznaky: ok=true, enabled=true, sessionValid=false, busy=false, backgroundLoginEnabled=true, locked=false, credentialEntryRequired=false, phase=idle a workPending=true. Tím je ověřen skutečný průchod novým pluginem k místnímu konektoru. Nešlo o volání původního Iris Tunel. Zůstává přepnutí pluginů v profilu hlavní Aidy a její vlastní stavový test. Přihlášení/MFA nebylo zahájené a obecný přístup k počítači se neobnovil.

Oprava předchozího postupu: Miloš neví, kde profil Aidy a přepínání pluginů najít. Ověřená [oficiální dokumentace](https://learn.chatgpt.com/docs/dots/computers-and-apps) uvádí použití podporovaných pluginů instalovaných a povolených pro účet, nikoli doložený samostatný seznam připojení v profilu dotu. Předchozí pokyn k výměně přímo v profilu byl neověřený a nesmí být vydáván za provedenou revokaci. Další test je přímý pokyn hlavní Aidě použít výhradně Iris Local a vrátit stav včetně eventId, bez MFA. Rozsah technického odebrání starého pluginu se ověří samostatně; dosud nebyl odebrán ani odinstalován a agent nemění celý účet jako náhradu za neověřené nastavení dotu.

Miloš následně předal odpověď hlavní Aidy označenou jako výsledek `iris_get_access_status` z Iris Local. Obsahuje stejný eventId 247149A1-25EB-4D9D-805F-1F1F79F01814 a stejné příznaky jako přímý test pluginu a místní smoke: ok=true, enabled=true, sessionValid=false, busy=false, backgroundLoginEnabled=true, locked=false, credentialEntryRequired=false, phase=idle, workPending=true. Aida výslovně uvedla, že přihlášení ani MFA nespustila. Vlastní spojení hlavní Aidy s tímto Macem je tím doložené uživatelským předáním odpovědi, nikoli přímým čtením její historie. Nejde o živé přihlášení, nové samostatné upozornění ani souhlas ke startu. Původní plugin dosud nebyl technicky odebraný; obecný přístup k Macu zůstává podle předchozího potvrzení odebraný. Následuje nové upozornění od Aidy a teprve následný přímý pokyn člověka pro místní živý MFA test.

## Živé přihlášení přes Aidu a Iris Local – úspěšné

18. října 2026 Miloš na výzvu k průchodu upozornění → nový pokyn Aidě → telefonní MFA odpověděl „hotovo, funguje“. Nativní sanitizovaný receipt z 18:22:36 Europe/Prague potvrdil authenticated, tokenSignatureVerified=true, readProbePassed=true, credentialsSubmittedByApp=true, automatickou volbu Plus4U Access a žádné validationFailures. Platnost ověřené relace končí v 18:52:35 Europe/Prague. Samostatný příznak mfaConfirmedByUser zůstal false: uživatel nestiskl diagnostické potvrzovací tlačítko, úspěch živého postupu doložil v konverzaci. Aplikace tím netvrdí kryptografické ověření druhého faktoru.

Následné skutečné stavové volání přes Iris Local potvrdilo ok=true, enabled=true, sessionValid=true, busy=false, phase=authenticated, backgroundLoginEnabled=true, credentialEntryRequired=false a workPending=false; requestId 67A349D3-4218-4E89-AE71-90609C13B409. Host má ready=true, running=true, failure=none. Mac byl odemčený (locked=false, backgroundAttempt=false), takže nejde o nové ověření zamčeného vývojového Macu. Implementační chat pouze četl stav; nevolal prepare, noticeSent ani start a nečetl přihlašovací UI nebo tajné hodnoty.

Komunikační a přihlašovací průchod na tomto Macu je nyní ověřený. Čtení identity není novým čtením úkolů a kalendáře; vlastní pracovní prostor a čtecí párování po nové relaci zůstávají samostatným krokem. Původní plugin Iris Tunel v účtu dosud nebyl odinstalovaný, samotné služby na Mini nejsou zastavené a jiné přímé +4U cesty nejsou tímto testem technicky odebrané.

## Původní plugin Iris Tunel odinstalován

Miloš výslovně schválil odinstalaci pouze původního pluginu Iris Tunel z celého ChatGPT účtu, s ponecháním Iris Local. Správa pluginů následně vrátila pro přesný název Iris Tunel stav uninstalled. Skutečné stavové volání přes ponechaný Iris Local poté znovu uspělo: ok=true, enabled=true, sessionValid=true, phase=authenticated, busy=false a workPending=false. Původní připojení k Mini je tedy z účtu odebrané; lokální komunikační a přihlašovací cesta zůstala funkční.

Odinstalace se netýkala nativních aplikací, klíčenky, API klíčů nebo samotného tunelu na Mini. Tyto komponenty se vzdáleně nezastavovaly ani neměnily. Nepovažovat odinstalaci za revokaci provozního API klíče nebo za dokončený audit dalších +4U pluginů a cloudového prohlížeče Aidy. Žádný nový login/MFA se nevyvolal.

Stavový dotaz podepsaného místního IrisRead následně vrátil pouze ok=false, error=transport. To není chyba autentizace přes Iris Local ani důkaz nefunkčních vzdálených uuCommandů; čtecí socket/párování zatím nejsou dostupné. Další krok je místní nalezení a potvrzení vlastního pracovního prostoru, párování čtecího klienta a čtecí pilot v nativním Iris Connect. Nečte se starý diagnostický výsledek jako důkaz nového čtení a nerozšiřují se čtyři MCP nástroje o pracovní agendu.

## Čtení v nové místní relaci – ověřeno

Miloš potvrdil dokončení vlastního prostoru, čtecího párování a pilotu. Validovaný sanitizovaný výsledek i přímý status podepsaného IrisRead nyní souhlasně vracejí ok=true, paired=true a loginRequired=false. Metadata pravidelného vlastněného souboru doložila novou aktualizaci 18. října 2026 v 18:28:13 Europe/Prague. Tasks.listActive: 2 183 aktivních DW záznamů, 11 stránek, complete=true a contractVerified=true. Calendar.list: 302 záznamů, dvě stránky; tasks.listFinal: 343 záznamů, dvě stránky. Obě poslední operace úspěšně přečetly data diagnosticky, ale stále mají contractPending a complete=false. Počet aktivních DW není počtem klasifikovaných pracovních úkolů.

Iris Local současně potvrdil sessionValid=true, authenticated, busy=false a workPending=false; host je ready s failure=none. Tím je dokončený základ místního nasazení: aplikace běží pod LaunchAgenty, Aida má doložené spojení novým soukromým pluginem, živý login/MFA uspěl a pracovní čtecí pilot je ověřený. Samostatné nedokončené podmínky: nový test zamčení a restartu tohoto vývojového Macu, časové kontrakty diáře/finálních stavů, audit dalších přímých +4U cest, rotace provozního klíče a pracovní služby Iris. Aida přes současné čtyři nástroje ještě nedostává agendu ani briefing. Přenos na Mini je odložený; jeho správní výpadek nebyl opravený.
