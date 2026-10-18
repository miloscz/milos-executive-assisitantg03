# Implementační plán Iris třetí generace

Plán z 18. října 2026 realizuje [dohodnutou architekturu](architecture.md). Nová Iris vzniká v tomto projektu. Komunikační agentka se jmenuje Aida (AI Dialogue Assistant) a běží na platformě Dot. Původní Iris zůstává během migrace provozuschopná; jednotlivé procesy převezme nová verze po ověření výsledků.

První funkční celek musí propojit skutečný úkol z +4U, přípravu řešení, rezervaci Milošova času, rozhodnutí přes Aidu a navazující dokončení. Dokumentace ani úspěšné spuštění modelu samy tento milník nesplňují.

Po ověření místního přihlášení a čtecí proxy Miloš schválil přípravu Macu mini pro Iris Connect a omezené MCP. Následuje [nasazení a ověření zamčené obrazovky](mac-mini-deployment.md); vývoj zůstává na současném Macu. První prototyp je popsaný v [návodu Iris Connect](../apps/iris-connect/README.md) a [záznamu ověření](iris-connect-verification.md).

## Navržené rozložení projektu

| Cesta | Účel |
| --- | --- |
| `apps/iris-connect/` | Nativní macOS aplikace, Keychain, přihlášení, MFA a vykonávání schválených operací. |
| `services/iris-core/` | Pracovní evidence, fronta, koordinace, scheduler a události. |
| `services/iris-mcp/` | Rozhraní a plugin pro Aidu. |
| `packages/contracts/` | Datové kontrakty, validace a verze rozhraní. |
| `packages/adapters/` | Mapování dat +4U, Signal a další doménové integrace. |
| `agents/` | Role, postupy, kontextové balíčky a kritéria výstupů. |
| `policies/` | Schválené operace proxy, časová pravidla a rozsahy autonomie. |
| `vault/` | Postupně převedené znalosti a trvalé výstupy. |
| `tools/migration/` | Opakovatelné převody, reporty a porovnání dat. |
| `tests/fixtures/` | Syntetická nebo anonymizovaná data pro ověření procesů. |
| `docs/` | Architektura, plán a následné záznamy rozhodnutí. |

Jde o cílovou strukturu; implementační adresáře se zakládají až s příslušnou funkcí. Provozní databáze, logy, dočasné soubory a zálohy dostanou samostatné umístění. Přístupové kódy a tokeny se nikdy nekopírují do projektu.

## Etapa 0 Ověření integračních předpokladů

### Přihlášení přes Iris Connect

**Aktuální výsledek:** místní prototyp je sestavený a základní živý průchod AC1/AC2 → potvrzení MFA → validace tokenu → čtení identity je ověřený. Záznam je v [ověření přihlášení](iris-connect-verification.md). Další body této etapy, zejména expirace, restart a zamčení, nejsou tímto průchodem automaticky ověřené.

Verze **0.2.2** živě ověřila jednorázovou automatickou volbu **Plus4U Access** uvnitř nativní aplikace: po zahájení přihlášení uživatel pouze potvrdil MFA na telefonu. Prošla validace tokenu i čtení identity a 24 automatických testů. Výsledky jsou v [záznamu přihlášení](iris-connect-verification.md). Zahájení přihlášení přes Aidu a upozornění před MFA zůstávají součástí jejího navazujícího napojení.

- Prověřit existující přihlašovací implementaci Iris a použitelný postup s Access Code 1 a 2 bez registrace nového klienta. Nepřebírat slepě přihlašovací konstanty ani předpokládat podporu MFA podle názvu grant flow.
- Postavit minimální nativní vstup kódů a uložení do Keychain. Zadání tajných údajů proběhne pouze v aplikaci.
- Ověřit přihlášení, MFA, expiraci pokusu, nové spuštění na pokyn a následné čtení jednoho skutečného zdroje.
- Ověřit, zda uživatel může přihlášení dokončit pouze potvrzením na telefonu, nebo potřebuje další interakci na Macu.
- Ověřit chování při zamčení obrazovky, restartu aplikace a nedostupné síti. Zachytit zjištěné limity v dokumentaci.

**Výstup:** ověřený přihlašovací postup, nebo přesně popsaná nevyřešená závislost. Pokud tok nelze doložit a zprovoznit, neprohlašovat přihlášení za hotové. Vývoj jádra může pokračovat nad testovacími daty.

### Propojení s Aidou

**MCP 0.1.0 implementované:** `services/iris-mcp` nabízí čtyři pevné řídicí operace přes stdio a podepsaného IrisControl. Všech 12 MCP testů včetně OS zákazu sítě, čtení souborů mimo službu a spuštění nepovolených programů prošlo také na Macu mini. Na cíli běží podepsané Iris Connect 0.4.1 a Iris MCP 0.1.4. Kvůli nesouladu cílového Swift toolchainu byly aplikace sestavené na vývojovém Macu. Živé přihlášení, lidské potvrzení MFA, párování a pracovní čtení jsou ověřené. Host tunelu po opravě YAML živě hlásí `ready`; 11 skupin policy testů a kontrola generovaného YAML oficiálním klientem prošly. Plugin Iris Tunel je registrovaný a jeho stavové volání z implementačního chatu živě prošlo i při zamčení. Miloš potvrdil odebrání obecného přístupu Aidy k Macu a následné volání pluginu opět uspělo. Miloš následně předal úspěšnou odpověď hlavní Aidy s výsledkem volání pluginu po revokaci. Přepnutí komunikační cesty je ověřené přímými testy a uživatelským potvrzením. Živý MFA průchod přes Aidu při zamčeném Mini také uspěl: Miloš potvrdil MFA telefonem a přímý stav pluginu v 16:40:50 Europe/Prague potvrdil sessionValid=true, authenticated, locked=true a busy=false. Zbývá kontrola ostatních přímých +4U cest, dřívějších úloh a provozu po restartu/odhlášení. [Nastavení a přepnutí](../services/iris-mcp/README.md), [záznam nasazení](mac-mini-deployment.md).

**Podmínka běžného provozu:** [bezpečnostní hranice Aidy](architecture.md#bezpečnostní-hranice-aidy-vůči-4u). Pilotní obecný přístup k Macu není cílové řešení. Před provozem musí úzké MCP rozhraní Iris nahradit přímé ovládání Macu a odstranit jiné přímé cesty Aidy a jejích úloh k +4U. Instrukce ani custom rules nejsou technickou izolací; pokud nelze omezit obecné síťové nástroje platformy, zákaz přímých HTTP volání není splněný. Ověřit také oddělenou instalaci nativního konektoru a kontrolu všech výstupů na syntetických tajných hodnotách. Skutečné kódy nebo token se při ověřování nečtou.

**Místní implementace 0.3.0:** oddělený `auth.sock` a podepsaný IrisControl, jednorázové upozornění, desetiminutové okno pro nový pokyn, idempotence a obnova bezpečného stavu po restartu. Pro první pilot je zvolen připojený Mac a místní úloha Aidy; vlastní MCP plugin ani tunel nejsou nainstalované. [Postup nastavení a stav ověření](../integrations/aida/README.md). Místní stav a prepare z Aidiny úlohy fungují po povolení konkrétního UNIX IPC příkazu mimo výchozí sandbox. Miloš potvrdil skutečné upozornění od Aidy; poté nativně prošel noticeSent a stav awaitingUser. Spuštění přihlášení přes Aidu, MFA a hlasové ovládání ještě ověřené nejsou. Samotná expirace bez čekající práce nevyvolá MFA ani upozornění. Push MCP Events zůstává budoucím krokem.

- Ověřit možnost připojit vlastní plugin v cílovém účtu.
- Zprovoznit jednoduché čtení testovacího briefingu a zaznamenání testovacího rozhodnutí.
- Ověřit stejné operace v hlasovém hovoru a zachování rozhodnutí po jeho přerušení.
- Ověřit událost „potřeba přihlášení“, upozornění před pokusem a pokyn „spusť přihlášení“. Nezaměňovat technické přijetí webhooku za přečtení zprávy uživatelem.
- Prověřit MCP Events včetně verze protokolu, odběrů, obnovy a deduplikace. Případná dočasná náhrada musí být viditelně popsána.

**Výstup:** obousměrné spojení Aida ↔ Iris s doloženým chováním během ranního hovoru.

## Etapa 1 Provozní jádro a pravidla proxy

**Schválený rozsah:** [čtecí rozhraní verze 1](iris-connect-read-policy.md) a [záznam schválení](../policies/iris-connect-read-v1.approval.json). Obsahuje čtyři commandy pro vlastní prostor, diář, aktivní a finální záznamy. Nativní implementace vynucuje schválený hash, ověřuje proces místního klienta a odděluje integrační pilot od provozního čtení. Živé výsledky a zbývající podmínky eviduje [stav čtecího rozhraní](iris-connect-read-verification.md).

- Zavést databázové migrace a entity pracovních položek, zdrojových záznamů, kroků, výstupů, rozhodnutí, schválení, rezervací, běhů a událostí.
- Zavést frontu s checkpointy, omezením běhu, omezeným souběhem a obnovou po restartu.
- Oddělit stav přípravy od oficiálního stavu úkolu v +4U.
- Definovat rozhraní Iris Connect a autentizaci spárovaného procesu. Agent nesmí získat tokeny ani obecný přístup k libovolné URL.
- Připravit seznam kandidátních operací s přesnými uuCommandy, cíli, validací parametrů, způsobem schválení a ověřením výsledku. Aktivovat pouze schválené položky.
- Převést obecné přihlašovací a MFA události na trvalý stav. Souběžné požadavky musí sdílet jeden přihlašovací pokus.
- Doplnit audit výsledků bez tajných údajů, zálohu databáze a ověřenou obnovu.

**Ověření:** restart neztratí práci; stejný požadavek nevytvoří duplicitu; nepovolený příkaz, workspace i parametr jsou odmítnuty; agent nemůže měnit politiku; změněný návrh nemůže použít staré schválení.

## Etapa 2 Spolehlivá agenda z +4U

- Portovat použitelné čtecí mapování z `iris-dwg-mcp`, přihlašování vést výhradně přes Iris Connect.
- Zavést úplné stránkování, evidenci rozsahu synchronizace a kontrolu částečných odpovědí. Úkol neuzavírat podle absence v omezeném časovém okně nebo jedné stránce.
- Rozlišit Milošovu elementární aktivitu, aktivitu jako celek, pozvánku a pracovní rezervaci.
- Pro výpočet kapacity načítat všechny blokující záznamy včetně osobního volna. Neúplnost dat explicitně označit.
- Synchronizovat podle stabilních identifikátorů, ukládat verze a čas aktuálnosti, změny zpracovávat idempotentně.
- Změnit vstup ze Signalu a dokumentů: nejprve znalosti nebo obohacení existujícího úkolu, samostatní kandidáti mimo osobní inbox.
- Nahradit pracovní markdownové seznamy generovanými pohledy nad evidencí. Historii zachovat.

**Ověření:** úkoly ve více než 200 záznamech se neztratí; částečný výpis neuzavře úkol; záznam bez termínu dostane explicitní zpracování; změna termínu nevytvoří novou položku; výpadek přihlášení nezničí poslední platný obraz.

## Etapa 3 Příprava důležité práce

- Zprovoznit znalostního agenta, agenta pro schůzky a agenta pro řešení úkolů nad společným kontraktem zadání a výstupu.
- Portovat relevantní skills, odstranit široké instrukce k ukládání každého nálezu do inboxu a k přímému Git zápisu každým agentem.
- Přidat kontextové balíčky se zdroji, aktuálností, rozhodnutími a rozpory. Zahrnout i relevantní práci mimo vault, pokud je zdroj zpřístupněný.
- Zavést zpětné plánování od termínu, explicitní závislosti a potřebný Milošův vstup.
- Vlastní přípravu vést jako kroky pod původním úkolem. Určit kritéria použitelného podkladu a kontrolu skutečně vytvořených artefaktů.
- Spouštět přípravu podle změn a předstihu, ráno již sestavovat přehled z hotových výsledků.
- Doplnit limity práce, prioritizaci a srozumitelné vysvětlení nedostatku kapacity.

**Ověření:** na skutečně vybraném důležitém úkolu vznikne použitelný výstup před potřebným rozhodnutím; chybějící vstup je viditelný; přerušený běh může pokračovat; tvrzení o dokončení odpovídá existujícímu výstupu.

## Etapa 4 Rezervace času a ochrana kapacity

- S Milošem stanovit pracovní hodiny, délky bloků, přestávky, rezervu pro operativu, pevné rezervace a limity přesouvání.
- Ověřit uuCommandy pro vytvoření a přesun vlastní rezervace a zařadit je do schválené politiky proxy.
- Přidat kontrolu aktuální dostupnosti před zápisem, evidenci záměru operace a kontrolní načtení po zápisu.
- Při nejasném výsledku nejprve zjistit skutečný stav, teprve poté případně opakovat.
- Rozpoznat ruční změnu a smazání rezervace uživatelem. Neobnovovat ji slepě.
- Při vytlačení pracovního času přepočítat proveditelnost závazku. Nabídnout náhradu nebo konkrétní kompromis přes Aidu.
- Přímé přesuny společných schůzek pro agenty zakázat.

**Ověření:** nevznikají duplicitní rezervace; souběžná změna kalendáře se zachytí; vlastní rezervaci lze přesunout; schůzka s dalšími účastníky ani nejasně klasifikovaná položka neprojde automatickým přesunem.

## Etapa 5 Ranní rozhovor a dotažení rozhodnutí

- Sestavit stručnou agendu dne s odkazy na připravené podklady, rezervovaný čas a výjimky.
- Přidat detail rozhodnutí, zaznamenání volby, změnu zadání a požadavek na dopracování.
- Ukládat verzi podkladu, ke které rozhodnutí patří, a potvrdit trvalé převzetí.
- Po rozhodnutí spustit navazující krok agenta a ověřit jeho výsledek.
- Oznámení směrovat podle významu; rutinní nezměněný stav nesmí zahlcovat Aidu.

**Ověření:** celý první funkční celek proběhne nad skutečným úkolem. Miloš může ráno probrat podklad, rozhodnout, hovor přerušit a později vidět správně navazující práci bez opakování rozhodnutí.

## Etapa 6 Koordinace přes Signal s Adélou

- Ověřit konkrétní kontakt Adély Babicové a použitelné odesílání ze současného Signal napojení. Současné čtení archivu samo o sobě odesílání neimplementuje.
- Přidat trvalé žádosti navázané na schůzku a konkrétní Milošovo schválení záměru.
- Připravit stručnou zprávu s důvodem, alternativami a termínem vyřešení; před odesláním znovu ověřit aktuálnost oken.
- Odeslání evidovat, nejednoznačné výsledky neopakovat slepě. Příchozí odpovědi korelovat s požadavkem.
- Po potvrzení zkontrolovat skutečný kalendář +4U a aktualizovat přípravy a bloky.
- Případné automatické připomínání zavést až podle dohodnutých pravidel.

**Ověření:** schválená žádost je doručena správnému kontaktu, odpověď aktualizuje správný požadavek a přesun je označen jako dokončený teprve po ověření kalendáře. Nevznikají další položky osobního inboxu ani duplicitní zprávy.

## Etapa 7 Dokončení migrace a provoz

- Převést zbývající znalosti, procesy a doménové adaptéry podle inventury.
- Rozšířit dashboard o připravenost dne, čekající rozhodnutí, vlastní bloky, závislosti, stáří dat a zdravotní stav integrací.
- Ověřit pravidelné zálohy a obnovu na čistém prostředí.
- Dokončit již zahájené nasazení na Mac mini a ověřit dostupnost, přihlášení při zamčení a omezené napojení Aidy.
- Vypnout nahrazené plánované joby původní Iris; zaznamenat přesně, kdo je vlastníkem každého zbývajícího procesu.

**Ověření:** žádný proces nemá dva aktivní zapisovače; přihlášení nevyvolává souběžné MFA pokusy; po restartu se obnoví práce; provoz nezávisí na globálním Git zámku; všechny důležité znalosti a rozhodnutí jsou dostupné i bez původního chatu.

## Postup migrace dat a procesů

1. Inventarizovat původní vault, skills, adaptéry, plánované joby a zdroje provozních dat. Zvolit rozsah prvního pilotu.
2. Vytvořit zálohu a migrační mapu zdrojových záznamů. Původní obsah nemazat.
3. Převádět po vybraných oblastech. Opravit interní odkazy a zachovat původ, historii a datum aktuálnosti.
4. Starý inbox zachovat jako archiv; aktivní položky propojit s +4U nebo jednotlivě posoudit. Hromadně nepřevzít všechny historické kandidáty jako aktuální závazky.
5. Nový proces nejprve porovnat se starým v režimu bez vnějších zápisů. Zkontrolovat úplnost, duplicity a výsledky.
6. Při přepnutí vypnout starý zapisující job, převzít checkpoint a určit jediného vlastníka synchronizace.
7. Při návratu na starý proces nejprve zastavit nový, vypořádat proběhlé vnější změny a checkpointy; znovu nepřehrát už provedené zápisy.

Přístupové kódy, tokenové soubory, `.env`, celé autentizační konfigurace a místní Signal credentials se nekopírují hromadně. Do nového repozitáře se přenášejí jen prohlédnuté zdroje a znalosti. Případný převod nahrávek a surových archivů má samostatný rozsah a úložiště.

## Pořadí závislostí

Etapa 0 má dvě nezávislá ověření: přihlášení a rozhraní Aidy. Jádro etapy 1 lze připravit nad fixtures, i když jedno ověření ještě čeká. Živá synchronizace etapy 2 potřebuje funkční přihlášení. Příprava etapy 3 může začít nad ověřeným exportem dat. Živé rezervace etapy 4 vyžadují aktuální kalendář a schválenou politiku. Etapa 5 propojí tyto části do prvního výsledku pro Miloše. Signal koordinace je další samostatný proces.

## Metriky pilotu

- Kolik důležitých úkolů má včas připravený další krok a podklady.
- Kolik potřebných rozhodnutí má rezervovaný čas před nejpozdějším vhodným termínem.
- Kolik úkolů se opozdilo kvůli nedostatku Milošovy kapacity a zda systém včas navrhl řešení.
- Kolik nevyžádaných kandidátů mimo +4U se dostalo do osobní agendy.
- Počet duplicitních položek, rezervací, zpráv a opakovaných rozhodnutí.
- Stáří dat, úspěšnost obnovy po výpadku a čas/náklady přípravy užitečného výstupu.

Číselné cíle se nastaví podle výchozího stavu a prvního pilotu. Do té doby se nemají vydávat domyšlené limity za dohodnuté požadavky.

## Probíhající provozní krok: restart Mini

Iris Connect 0.5.0 a Iris MCP 0.2.0 jsou sestavené, podepsané a nasazené. Pod účtem irisagent jsou nainstalované dva GUI LaunchAgenty a oba joby skutečně běží. Nové místní souhlasy obnoví jen shodné podepsané párování a transport, nikoli token, starý pokyn nebo MFA. Miloš potvrdil zapnutí místních voleb. Kontrolovaný restart obou aplikací obnovil párování i transport bez místního kliknutí a bez MFA; přímé volání pluginu poté uspělo (první pokus po výměně procesů měl timeout). Následuje živý restart macOS s novým bootTime a následným testem MCP. Nezaměňovat tyto tři důkazy. Čtení vlastního prostoru a provoz po odhlášení/uspání zůstávají oddělené.

## Navazující návrh: rotace provozního klíče tunelu

U 30denního klíče navrhnout asistovanou nativní výměnu s kandidátním Keychain slotem, krátkým překryvem platnosti, jedním klientem stejného tunelu, skutečným MCP kontrolním voláním, návratem při chybě a následnou ruční revokací starého klíče na Platform. Provozní klíč zůstane jen Read + Use; žádný admin klíč pro Aidu nebo MCP. Metadata expirace a cloudové upozornění musí fungovat nezávisle na životnosti tunelu. Rotace zatím není implementovaná a nebyla vytvořená žádná připomínková automatizace. Podrobnosti v services/iris-mcp/README.md. Aktuální ověření automatického spouštění zůstává rozpracované a čeká na místní kroky člověka.

Miloš následně potvrdil skutečný restart macOS. Iris Tunel po něm přímo odpověděl a Connect měl obnovené párování bez běžícího loginu. Současně aktualizace NordVPN na Mini podle uživatele vyžádala administrátorské heslo a zanikla dostupná správní cesta. Obnova SSH/Sdílení obrazovky a nezávislé ověření nového bootTime nyní předcházejí dokončení provozního testu. Neoznačovat správní výpadek za opravený ani Mini za plně bezobslužné; příčina a potřebné místní kroky zatím nejsou potvrzené.

Obnova místního Meshnet a následný výslovně schválený Reconnect hlavní NordVPN na vývojovém Macu správu Mini neobnovily. Mini se přitom zobrazuje online s obousměrným oprávněním vzdáleného přístupu. Iris Tunel nadále živě odpovídá. Další krok vyžaduje jinou již nastavenou správní cestu nebo místní zásah; omezené MCP se kvůli opravě nerozšiřuje.

## Aktuální priorita: nejprve provoz na tomto Macu

Miloš po neúspěšné obnově správy rozhodl rozjet Iris Connect a omezené MCP na vývojovém Macu a přenos na Mini odložit. Podepsané verze 0.5.0 a 0.2.0 zde byly ověřené a spuštěné pod stejnými dvěma uživatelskými LaunchAgenty s explicitním cílem `current-mac`. Prošlo 12 MCP testů včetně skutečné OS izolace a tři testy instalačního pomocníka. Místní MCP discovery potvrdilo přesně čtyři nástroje; stav vrací unavailable do nového místního povolení člověkem. Tunel hostu je zastavený, login/MFA neproběhl.

Pořadí: místní převzetí klientské konfigurace nativní aplikací a kontrola Keychain → lidské povolení řídicího párování a jeho obnovy → stavový smoke → nový soukromý tunel a plugin Iris Local → ověření přímého stavového volání novým pluginem → přepnutí Aidy pouze na Iris Local a ověření její odpovědi → teprve po novém upozornění a přímém pokynu živé MFA a samostatné ověření pracovního čtení. Původní tunel na nedostupném Mini se zde nesmí použít souběžně. Dosud není ověřený běžný provoz Aidy na tomto Macu. Žádná přístupová data se mezi hosty nepřenášejí a Aida nedostává obecný přístup.

Místní souhlasy Miloš potvrdil a skutečný stavový smoke uspěl. Nový místní tunel následně přešel do ready, running=true a failure=none, nezávisle ověřeno sanitizovaným receiptem. Aktuálně zbývá vytvořit soukromý plugin Iris Local nad tímto tunelem, ověřit jej přímo a přepnout Aidu; samotná připravenost transportu přepnutí nedokládá.

Vytvoření pluginu Iris Local a čtyři nástroje již Miloš potvrdil. Dalším krokem je zpřístupnění jeho nástrojů implementačnímu chatu a skutečné stavové volání přes tento nový plugin; katalog zde stále obsahuje pouze původní Iris Tunel. Přepnutí Aidy ani cloudový průchod k místnímu hostu tedy ještě nejsou ověřené.

Po připojení pluginu k tomuto chatu skutečné stavové volání přes Iris Local uspělo; paralelní místní MCP smoke vrátil stejný eventId a stejné příznaky. Průchod plugin → nový soukromý tunel → místní omezené MCP → podepsaný IrisControl → místní Iris Connect je ověřený. Nyní zbývá přímý pokyn hlavní Aidě používat Iris Local a její vlastní stavový test. Samostatné přepínání pluginů v profilu dotu nebylo ověřené; oficiální dokumentace popisuje pluginy povolené pro účet. Technické odebrání dostupnosti starého pluginu vyžaduje oddělené ověření rozsahu a není splněno pouhým pokynem Aidě. Žádný start ani MFA se v implementačním chatu nevolal.

Vlastní stavové volání Aidy přes Iris Local je nyní uživatelsky doložené předanou odpovědí se stejným eventId jako místní konektor. Následuje místní živý průchod upozornění → nový přímý pokyn → MFA na telefonu → potvrzená relace přes Iris Local. Dosud jde jen o stavové ověření bez platné relace. Technické odebrání původního pluginu a dalších přímých +4U cest není tímto testem splněné.

Živý místní průchod nyní uspěl: Miloš potvrdil úspěch postupu přes Aidu a telefonní MFA; nativní záznam v 18:22:36 Europe/Prague potvrdil podpis tokenu a čtení identity, následné Iris Local volání sessionValid=true, authenticated a busy=false. Mac byl odemčený. Přihlášení na tomto Macu přes nový omezený plugin je ověřené; nejde o nový test zamčení, restartu, úplnosti agendy nebo odebrání ostatních cest. Další kroky jsou vyřazení původního pluginu po vyjasnění rozsahu změny účtu, místní čtecí párování a živé ověření úkolů/kalendáře v nové relaci. Rotace klíče a pracovní služby Iris zůstávají samostatná nedokončená práce.

Původní Iris Tunel byl nyní po výslovném souhlasu Miloše odinstalován z účtu; správa pluginů potvrdila uninstalled. Iris Local následně znovu odpověděl s platnou relací, authenticated a busy=false. Vyřazení tohoto starého pluginu je dokončené, nikoli revokace klíčů nebo vypnutí aplikací na Mini. Další přímé +4U cesty zůstávají k oddělenému auditu. Následuje čtecí párování a ověření úkolů/kalendáře v aktuální místní relaci.

Místní čtecí párování a nový pilot nyní také uspěly, potvrzené uživatelem, validovaným záznamem aktualizovaným v 18:28:13 Europe/Prague i přímým IrisRead status. Aktivní DW: 2 183 záznamů přes 11 stránek, complete=true. Diář: 302 záznamů přes dvě stránky; finální DW: 343 záznamů přes dvě stránky, oboje stále contractPending a complete=false. Základ místního nasazení Connect + omezené MCP je ověřený. Další práce před spolehlivými briefingy a plánováním zahrnuje doložení kalendářních/finálních kontraktů, klasifikaci DW a služby Iris; rozšíření čtyř MCP nástrojů o agendu zatím není implementované. Restart a zamčení tohoto vývojového Macu, bezpečná rotace klíče a audit ostatních +4U cest mají samostatné podmínky. Mini zůstává pozdějším cílem.

## První ranní briefing a kalibrace kalendáře – probíhá

Na výslovný pokyn Miloše byl dosavadní ověřený stav uložen prvním commitem `fadc476` (69 zdrojových a dokumentačních souborů). Prošlo 33 nativních, 12 MCP a osm pomocných syntetických testů. Kontrola před commitem našla pouze záměrné syntetické přihlašovací konstanty v testech, žádné provozní hodnoty; build a osobní data se necommitují.

Následně je implementovaná a podepsaná verze Connect 0.6.0 s pevnou read-only kalibrací časových hranic. Změny mají 36 nativních testů. Dokumentace z uuKnowledgeBase doložila výběrový DAO predikát a nezávislé stránkování, nikoli zónu a převod vstupních datumů. Explicitní UTC adaptér proto musí projít živým porovnáním širšího okna, aktivních blokujících záznamů, sousedních dnů a přesných hranic existujících událostí. Bez úspěchu nepovolí běžná kalendářní data. Žádné testovací události se nezapisují.

První lokální compiler `services/iris-core/briefing.py` připravil soukromý náhled na pondělí 19. října 2026 ze schváleného normalizovaného aktivního seznamu. Obsah není v Gitu. Nový pátý MCP nástroj `iris_get_morning_briefing` bez parametrů čte jen tento jediný připravený soubor. Prošlo 14 MCP testů včetně zachování OS izolace a dvou nových kontrol výstupu, dva testy compileru a skutečné čtení připraveného náhledu přes sandboxované stdio MCP. Neúplný kalendář a stáří přes 30 minut se výslovně označují, přihlášení se nevyvolává.

Po ověření nečinné relace byly oba joby bezpečně zastavené, předchozí bundle zachován a ověřený Connect 0.6.0 nasazen. Host tunelu zůstal ve verzi 0.2.0 a po restartu sám přešel do ready; spouští nový MCP server 0.2.0. Nyní se čeká na nové místní souhlasy, přihlášení a čtecí párování člověkem. Dále je potřeba živá kalibrace, obnovení podkladů briefingu, aktualizace katalogu Iris Local o pátý nástroj a skutečné předání Aidou. Nasazení nebo lokální stdio smoke samo toto předání nedokládá. Ranní pravidelný scheduler a úplná příprava zdrojových dokumentů nejsou součástí tohoto prvního compileru.

### Oprava po prvním živém pokusu 0.6.0

Miloš potvrdil nové přihlášení a párování. Kalibrace s ISO timestampy selhala jako httpFailure; stejná relace dál úspěšně načetla původní datumový pilot. Přesná serverová příčina není doložená. Oprava 0.6.1 proto používá doložené date-only parametry, UTC obálku a přesný místní filtr. Má 37 úspěšných nativních testů a oddělený podepsaný build. Živá kalibrace opravy a obnova katalogu pátého nástroje v Iris Local zůstávají otevřené. Uživatel v detailu nenašel Refresh; neopakovat neověřený návod. Soukromý náhled briefingu byl znovu aktualizován přes podepsaný IrisRead a stále výslovně hlásí activeRecordsOnly (11 bloků, 3 priority, 2 konflikty).

Oprava Connect 0.6.1 byla následně bezpečně nasazená po potvrzení sessionValid=true, busy=false a authenticated přes Iris Local. Původní bundle je zachovaný. Oba uživatelské joby běží a host tunelu znovu hlásí ready; žádný login ani MFA se při nasazení nespustil. Čeká se na místní kroky člověka v nové podepsané aplikaci.
