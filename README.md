# Iris třetí generace

**Aktuální stav:** Connect 0.6.2 prošel živou kalibrací časových hranic i běžným čtením kalendáře. První soukromý briefing na pondělí 19. října vznikl z ověřeného kalendáře: 11 bloků, 3 priority a 2 konflikty. Čtení uspělo i přes skutečný cloudový Iris Local. Chybu prvního pokusu Aidy odstranil úklid starých tunelů a host 0.2.1 s ukončováním potomků a zámkem jedné instance; prošel i živým restartem. Miloš následně potvrdil, že Aida po opravě vypsala stručný ranní briefing; textové předání je ověřené. Hlasový průchod zatím ověřený není. Jde o večerní přípravu, před ranním použitím je potřeba obnovit zdroje. Podrobné dokumentové podklady, pravidelný scheduler a pracovní zápisy nejsou hotové. [Doložené výsledky a limity](docs/iris-connect-read-verification.md), [postup](docs/implementation-plan.md).

Osobní pracovní systém Miloše Vodrážky. Iris průběžně připravuje řešení úkolů, podklady k rozhodnutí a přípravy na schůzky. Aida (AI Dialogue Assistant), komunikační agentka postavená na platformě Dot, slouží jako hlavní partnerka pro rozhovor, zejména při ranní cestě autem. Znalosti, stav práce a procesní know-how zůstávají v systému Iris.

Hlavním cílem je začínat důležitou práci včas a vyhradit prostor pro to, co musí rozhodnout nebo udělat Miloš. Hlavním zdrojem závazků jsou úkoly a schůzky v +4U. Informace z dalších zdrojů nesmějí automaticky přeplňovat inbox.

## Dokumentace

- [Architektura a dohodnuté chování](docs/architecture.md)
- [Plán implementace a migrace](docs/implementation-plan.md)
- [Iris Connect a spuštění místního prototypu](apps/iris-connect/README.md)
- [Omezené MCP rozhraní a přepnutí Aidy](services/iris-mcp/README.md)
- [Místní propojení Aidy a řízení MFA](integrations/aida/README.md)
- [Stav ověření přihlášení](docs/iris-connect-verification.md)
- [Schválené čtecí commandy a omezení proxy](docs/iris-connect-read-policy.md)
- [Výsledky živého čtení úkolů a kalendáře](docs/iris-connect-read-verification.md)

Dokumentace zachycuje dohodu z 18. října 2026. Produktová rozhodnutí jsou odlišena od navržené technické realizace a dosud neověřených integračních možností. První implementovanou částí je místní nativní prototyp Iris Connect. Přihlášení pomocí uživatelem zadaných AC1/AC2, potvrzení MFA, validace tokenu a čtení identity z +4U byly živě ověřeny na tomto Macu.

## Umístění nové Iris

Tento repozitář je cílovým domovem nové Iris: aplikace Iris Connect pro macOS, provozní služby, agentů, procesních postupů a postupně převedené znalostní báze.

Původní Iris je v `/Users/milosvodrazka/Personal/milos_executive_assistant`. Slouží jako zdroj znalostí a použitelných implementací. Převod bude postupný po jednotlivých procesech; původní provoz se vypne až při převzetí odpovědnosti novou verzí.

Lokální provozní databáze, dočasné pracovní soubory a logy budou oddělené od verzovaných zdrojů. Přihlašovací údaje a tokeny budou spravované aplikací Iris Connect v macOS Keychain, mimo repozitář a dosah agentů.

## Názvy

- **Iris** označuje pracovní systém a jeho agenty.
- **Iris Connect** je pracovní název nativní macOS brány do +4U.
- **Aida** znamená **AI Dialogue Assistant**. Je to komunikační agentka postavená na platformě Dot; vede rozhovory s Milošem, vysvětluje možnosti a předává jeho rozhodnutí Iris. České oslovení je **Aido**.
- **Dot** zůstává označením platformy, na které Aida běží.
- **Adéla Babicová** je lidská executive assistant a koordinuje přesuny schůzek s dalšími účastníky přes Signal.

## První ověřitelný výsledek

U jednoho skutečného úkolu z +4U systém připraví řešení s předstihem, zajistí čas pro Milošův příspěvek, předloží podklad přes Aidu a po rozhodnutí ověřitelně pokračuje. Přípravné kroky agentů přitom nevytvářejí další položky v Milošově inboxu.

Přihlášení s Access Code 1 a 2, potvrzením MFA a čtením identity funguje bez registrace nového OIDC klienta, s využitím existující konfigurace Iris. Build 0.2.0 přidal schválenou čtecí proxy a podepsaného místního klienta. Živě načetl 2 183 aktivních DW záznamů přes 11 stránek, 302 diářových a 343 finálních záznamů. Aktivní záznamy jsou dostupné přes běžné rozhraní; diář a finální seznam zůstávají v diagnostickém režimu do ověření časových kontraktů. Verze **0.2.2** živě ověřila automatickou volbu Plus4U Access a přihlášení, při kterém po zahájení stačilo potvrdit MFA na telefonu. Verze **0.3.0** přidává samostatné místní řízení přihlášení pro Aidu přes podepsaný IrisControl. Místní spojení se spárovaným IrisControl je živě ověřené; uživatel potvrdil připojení Macu k Aidě. Kontrola z Aidiny úlohy, příprava požadavku a skutečné upozornění od Aidy jsou živě ověřené; doručení potvrdil Miloš. Navazující spuštění přihlášení a MFA přes Aidu ještě ověřené nejsou; podrobnosti jsou v [návodu propojení](integrations/aida/README.md). Datový model a pracovní procesy jsou další kroky.

**Aktuální cíl:** po výpadku vzdálené správy Mini Miloš rozhodl nejprve rozjet provoz na tomto Macu a přenos na Mini dokončit později. Na tomto Macu běží podepsané Iris Connect 0.5.0 a Iris MCP 0.2.0 pod uživatelskými LaunchAgenty. Místní párování, nový soukromý tunel a skutečné stavové volání přes Iris Local jsou ověřené. Miloš předal odpověď hlavní Aidy se stejným eventId jako místní konektor a následně potvrdil úspěch živého přihlašovacího testu. Dne 18. října 2026 v 18:22–18:23 Europe/Prague nativní záznam potvrdil podpis tokenu a čtení identity; Iris Local potvrdil sessionValid=true, authenticated a busy=false při odemčeném Macu. Následný nový čtecí pilot v 18:28 a přímý IrisRead status potvrdily párování i úspěšné čtení aktivních DW, diáře a finálních DW. U diáře a finálních DW nadále platí contractPending; jejich úplnost pro plánování není ověřená. Zamčení a restart tohoto vývojového Macu mají samostatné nedokončené testy. Aida přes čtyři současné MCP nástroje zatím řídí jen přihlášení, nikoli přístup k agendě nebo briefingům. Původní plugin Iris Tunel byl po výslovném souhlasu odinstalován z účtu; následná kontrola Iris Local znovu uspěla. Audit dalších přímých +4U cest zůstává samostatný. Aplikace na Mini nebyly zastavené, a proto se zde používá jiné ID tunelu. [Postup a stav nasazení](docs/mac-mini-deployment.md).

## Omezené MCP 0.1.0

Implementované jsou čtyři řídicí nástroje pro stav, přípravu upozornění, potvrzení jeho odeslání a jednorázový start přihlášení. Živé místní čtení stavu přes MCP a podepsaný IrisControl je ověřené. Všech 12 MCP testů prošlo včetně OS zákazu sítě, čtení syntetického souboru mimo službu a spouštění jiných programů. Nativní host `build/Iris MCP.app` bezpečně přijímá pouze provozní klíč OpenAI do vlastní klíčenky; 11 syntetických skupin ověřilo jeho vstupy, loopback URL a zápis konfigurace.

Secure MCP Tunnel na Macu mini po místním startu živě hlásí připravenost; agent ji potvrdil sanitizovaným stavem. Soukromý plugin **Iris Tunel** je registrovaný a jeho volání stavu z tohoto chatu živě prošlo i při zamčeném Macu mini. Miloš potvrdil odebrání obecného přístupu Aidy k Macu a následné volání pluginu z tohoto chatu znovu uspělo. Miloš následně předal i úspěšnou odpověď hlavní Aidy po volání stavu přes plugin, bez MFA. Kontrola ostatních přímých +4U cest ještě není dokončená. Agent žádný skutečný provozní klíč nedostal. Na Macu mini jsou nyní nasazené Iris Connect 0.5.0 a Iris MCP 0.2.0. Host zahrnuje dřívější opravu zápisu YAML odmítaného klientem tunelu. Oprava prošla oficiálním klientem na syntetických datech. 12 testů omezeného MCP prošlo přímo na cíli. Místní přihlášení s lidsky potvrzeným MFA, čtení úkolů/kalendáře a párování prošly. Připojení Aidy přes soukromý plugin je doložené přímými testy a uživatelským potvrzením její odpovědi. 18. října 2026 v 16:40 Europe/Prague prošel také živý MFA průchod přes Aidu při zamčeném Mini: uživatel potvrdil MFA telefonem a přímý stav pluginu potvrdil platnou relaci, authenticated, locked=true a ukončený pokus. Chování po restartu/odhlášení tím ověřené není. [Postup přepnutí a technické hranice](services/iris-mcp/README.md).

## Spouštění po přihlášení do macOS

Dva uživatelské GUI LaunchAgenty jsou nainstalované a aplikace pod nimi běží. Connect 0.5.0 dovoluje místně schválit obnovení párování stejné podepsané verze; host 0.2.0 dovoluje místně zapnout automatické připojení tunelu bez interaktivního čtení klíčenky při startu. +4U login/MFA se po startu nikdy sám nevyvolá. Místní volby jsou zapnuté a kontrolovaný restart obou aplikací obnovil párování i tunel bez kliknutí a bez MFA. Po uživatelem potvrzeném restartu macOS plugin opět uspěl bez ručního otevření Iris aplikací. Správní přístup přes NordVPN/SSH/Sdílení obrazovky nyní nefunguje a vyžádal obnovu; nový bootTime ani plně bezobslužný provoz zatím nejsou nezávisle ověřené; [aktuální záznam](docs/mac-mini-deployment.md).
