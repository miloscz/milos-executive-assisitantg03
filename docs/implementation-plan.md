# Implementační plán Iris třetí generace

Plán z 18. října 2026 realizuje [dohodnutou architekturu](architecture.md). Nová Iris vzniká v tomto projektu. Komunikační agentka se jmenuje Aida (AI Dialogue Assistant) a běží na platformě Dot. Původní Iris zůstává během migrace provozuschopná; jednotlivé procesy převezme nová verze po ověření výsledků.

První funkční celek musí propojit skutečný úkol z +4U, přípravu řešení, rezervaci Milošova času, rozhodnutí přes Aidu a navazující dokončení. Dokumentace ani úspěšné spuštění modelu samy tento milník nesplňují.

Po ověření místního přihlášení a čtecí proxy proběhl pilot na Macu mini, ale po výpadku jeho správy Miloš rozhodl nejprve dokončit místní provoz. Přenos na Mini zůstává odložený; [historie nasazení a stav obou hostů](mac-mini-deployment.md) nejsou novým pokynem k pokračování na Mini. První prototyp je popsaný v [návodu Iris Connect](../apps/iris-connect/README.md) a [záznamu ověření](iris-connect-verification.md).

## Aktuální přehled a chybějící části – 18. října večer

Tento přehled rozlišuje skutečnou implementaci od cílových etap a historických záznamů níže. Celý první funkční celek z úvodu dosud hotový není. Živý briefing a rozhovor nepotvrzují trvalé převzetí rozhodnutí ani dotažení práce.

| Oblast | Doložený stav | Co ještě chybí |
| --- | --- | --- |
| Přihlášení a omezené MCP | Místní živé čtení, řízené lidské MFA a Iris Local ověřené; obecný přístup Aidy odebraný podle Milošova potvrzení. | Úplný audit ostatních přímých cest a oddělení provozní instalace od zapisovatelného vývoje. |
| Agenda a podklady | Kalendář a aktivní úkoly se stránkují; Elementary i čtyři typy ManagementKit živě prošly. | Trvalá evidence změn a verzí všech pracovních položek, úplná klasifikace pro budoucí zápisy a další nepodporovaný obsah. Přílohy nejsou schválenou součástí současného čtení. |
| Briefing a hlas | Miloš potvrdil hlasový rozhovor. Po přihlášení 19. října vznikla aktuální publikace v 9:30:35 se zdroji z 9:26:29, pět obsahových analýz a čerstvý detail přes Iris Local. Potvrdil jedinou rutinu Aidy v 6:45/7:00/18:00 s podmíněným upozorněním na MFA a sledováním přípravy po přihlášení. | Ranní předání v 7:00 neprošlo; část podkladů zůstává neúplná. Stabilní čekání je opravené, nové skutečné upozornění ještě vyžaduje živé ověření. Průběžné pětiminutové kontroly na notebooku Miloš odmítl, místní dokončování má původní interval; trvalý dohled se řeší až na Mini. |
| Pracovní jádro | SQLite fronta briefingů; navíc živý soukromý P1 pro dvě pracovní položky, jejich verze, přípravu, znalosti a vstupy. | Obecný adaptér, závislosti, rozhodnutí, schválení a rezervace. Stabilní nativní vazba v 0.8.0 je živě ověřená i po dalším přihlášení; ID a historie zůstaly zachované. Tabulka jobs ani omezený P1 nejsou celé jádro. |
| Knowledge base | Inventura a živý P1 se sedmi tvrzeními, původem, daty a rozlišením interpretací a kandidátů rozhodnutí. | Plný spravovaný Markdown vault/index, znalostní agent a řízené aktualizace ve více oblastech. Pro oblast nahrávání schůzek je implementované zapojení kontextu do večerní/ranní přípravy a omezený detail pro Aidu; živá publikace i místní omezené MCP prošly; Miloš potvrdil použití detailu hlavní Aidou. |
| Agenti a know-how | Ranní/večerní dávka má vlastní ohraničený obsahový krok po načtení zdrojů; živé ověření automatického dokončení a inference se eviduje v runbooku. | Znalostní, schůzková a úkolová role, společná zadání/výstupy, limity běhů a migrace použitelných postupů původní Iris. |
| Inbox a vstupní filtr | Pravidla a živé směrování tří historických vstupů v P1 bez nových osobních úkolů. | Rutinní zapojení dalších zdrojů a převzetí starých zapisujících procesů; původní Iris se zatím neupravuje ani nevypíná. Starý inbox se P1 nevyčistil. |
| Rozhodnutí z hovoru | MCP 0.5.0 přidává verziovanou frontu dopracování a dvoufázový místní záznam rozhodnutí. Skutečné zadání Aidou i dokončené dopracování přes MCP prošly; první lidské potvrzení bylo správně odmítnuté pro stáří podkladu. Oprava 0.5.1 objednává nové čtení; živá obnova nyní čeká na přístup. | Úspěšný živý readback a záznam po obnově podkladu, budoucí externí provedení podle samostatných oprávnění a ověřeného výsledku; technické ověření hlasové identity není současným příznakem souhlasu doložené. |
| Proaktivní příprava a kapacita | Večerní/ranní dávka a jednoduchý výběr priorit. | Předstih v týdnech, zpětné plánování, odhady potřebného Milošova času, závislosti, ohrožené termíny a konkrétní výstupy úkolového agenta. |
| Kalendářní zápisy | Produktově povolené vlastní rezervace podle budoucích pravidel; žádné aktivní zapisovací commandy. | Časová pravidla, přesné commandy a jejich schválení, kontrola konfliktu a výsledku, zacházení s ruční změnou rezervace. |
| Signal a Adéla | Cílový proces popsaný; obecné čtení archivu není odesílání. | Migrace potřebných vstupů, ověření kontaktu a schváleného doručení, přiřazení odpovědí a následné ověření skutečné změny kalendáře. |
| Provoz a migrace | Místní služby, obnova aplikačních procesů, řízené párování a ochrana proti nečinnému uspání. | Bezpečná rotace 30denního klíče, zálohy a skutečná obnova pracovní evidence/KB, provozní přehled, úplná migrace a jediný vlastník každého procesu. Mini je vědomě odložené po výpadku správy. |

Nejbližší doporučené pořadí: doplnit potřebný základ pracovní evidence z etap 1–2 a inventuru/KB se vstupním filtrem; nad jednou pracovní oblastí propojit znalostního a úkolového agenta, přípravu a trvalé převzetí rozhodnutí; poté doplnit zpětné plánování a ochranu kapacity. Ranní provozní test a provozní nedostatky sledovat samostatně. Jde o upřesnění závislostí a návrh další práce, nikoli aktivaci nových MCP operací, +4U zápisů, migrace nebo komunikace třetím osobám.

**P1 je živě ověřený v omezeném rozsahu:** [inventura](legacy-inventory.md), [vymezení](work-knowledge-pilot.md), [soukromé úložiště](private-work-storage.md) a [důkaz dvou čtení](work-knowledge-pilot-verification.md). Dvě pracovní položky, dva přípravné kroky a sedm tvrzení zůstaly bez duplicit. Záloha byla obnovena do oddělené databáze se shodou všech řádků. Prošlo 31 testů jádra. Navazuje [stabilní vazba a znalostní příprava s doptáváním](stable-binding-and-followup.md): Connect 0.8.0 a šestý omezený MCP nástroj jsou nasazené, Miloš potvrdil místní souhlasy a šest nástrojů. Živá příprava prošla se zachováním ID a historie bez duplicit. Druhé běžné přihlášení zachovalo stejnou vazbu, ID i historii; Miloš také doložil správné předání detailů hlavní Aidou. Navazuje [pracovní předání přes Aidu](aida-work-handoff.md): dopracování je živě přijaté i dokončené, rozhodovací protokol je nasazený a jeho lidský průchod se ověřuje. Dále zbývá konkrétní řízené provedení a převzetí původního zapisujícího procesu. Původní Iris a ranní rozvrh zůstaly beze změny; první celý funkční celek z úvodu ani plná KB tím dokončené nejsou.

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

Aktuální navazující práce: [automatická příprava a ranní obnova](briefing-automation.md). Miloš potvrdil 18:00 a 7:00 v pracovní dny, Europe/Prague, a požaduje rovnou dokumenty i schůzky uuManagementKit. Společné čtecí rozšíření Miloš schválil s doplněním `keyTask` a `request`; přesná specifikace i schválení jsou v policies. Nativní implementace a živé piloty jsou navazující podmínkou aktivace. Původní návrh pouze pro Elementary Management nebyl schválený. Rutinní zdrojové čtení, fronta, obnova čtecího párování po MFA a pravidelné předání Aidou mají samostatná kritéria dokončení v navazujícím dokumentu.

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

### Kalibrace 0.6.1 a další ověření

Živá kalibrace v 18:59:55 potvrdila širší pokrytí, aktivní záznamy, sousední dny a přesný místní filtr. Sedm dayBlock a čtyři vícedenní položky. Den podzimní změny má 25 hodin, ale žádné živé položky; netvrdit otestování přechodu události. Předpoklad serverové UTC půlnoci neprošel, proto kalendář zůstal zavřený.

Verze 0.6.2 má čtyři pevné modely datumových parametrů (UTC/pražská půlnoc, UTC/pražský celý koncový den), explicitně vrací všechny shody a kontroluje schválený 93denní limit i po obalení. Prošlo 38 nativních testů. Nový podepsaný build byl bezpečně nasazen pouze výměnou zastaveného Connectu; MCP host zůstal beze změny. Čeká se na místní souhlasy, login a párování.

Ze snímku Iris Local je doložené tlačítko Spravovat, kde uživatel našel Znovu načíst nástroje. Po dokončeném obnovení stále viděl čtyři. Místní katalog prokazatelně nabízí pět a cloudový stavový nástroj vrací stejný eventId jako místní pomocník. Samostatná obnova MCP hosta narazila na přechodnou chybu registrace jobu; po dokončení ukončení a opakované registraci je host znovu ready. Následuje jediné nové obnovení katalogu nad novým spojením. Předání briefingu Aidou zatím není doložené.

### Kalendář a první briefing ověřené – 19:17 Europe/Prague

Miloš potvrdil novou relaci 0.6.2 s telefonním MFA a pět nástrojů po obnovení Iris Local. Pevná kalibrace v 19:17:25 uspěla: širší okno, aktivní pokrytí, sousední dny i přesný filtr souhlasí. Shodují se oba modely celého koncového dne, UTC a Prague; vzorek nerozlišuje zónu a adaptér to netvrdí. Obálka a místní filtr pokrývají oba. Sedm dayBlock a čtyři vícedenní vzorky; den změny času 25 hodin, ale bez živých položek. Calendar.list je aktivované jen pro tuto relaci; finální kontrakt není tímto vyřešený.

Compiler následně vytvořil briefing na 19. října 2026 z ověřeného kalendáře, coverage=verified: 11 bloků, 3 priority a 2 souběhy. Skutečný sandboxovaný MCP výstup má freshness=current a shodná metadata. Nejstarší zdroj 19:17:13, tedy večerní příprava; před ranním použitím obnovit. Detailní zdrojové dokumenty stále chybí, žádné rezervace nebo schválení neproběhly. Přímé předání Aidou čeká na její skutečné volání pátého nástroje a potvrzení výsledku; tento implementační chat zatím nabízí pouze původní čtyři nástroje, proto jeho nedostupnost není důkazem neúspěchu obnoveného katalogu Aidy.

### Oprava doručovací cesty po chybě Aidy

Aida v 19:19 ohlásila invalidRequest při iris_get_morning_briefing. Skutečný cloudový test chybu zopakoval, místní stdio ale fungovalo. Byly nalezené tři osiřelé staré tunely s MCP potomky vedle aktuálního hosta; kontrolovala se jen metadata procesů. Přesný úklid a nové připojení vedly k úspěchu cloudového čtení. Host 0.2.1 následně dostal zámek jedné instance, zachycení TERM/INT a ukončení celé vlastní skupiny workeru včetně potomka. Prošel syntetický test obou signálů, potomků, duplicity a obnovení zámku, pět testů sanitizovaného stavu a podepsané sestavení.

Nasazená 0.2.1 prošla i živým restartem pouze MCP jobu: všechny tři staré procesy zanikly bez ručního zásahu, host se vrátil do ready a následné skutečné cloudové stavové volání i briefing uspěly. První požadavek po restartu měl přechodný timeout, jeho příčina není prokázaná. Connect ani jeho přihlášení se neměnily, nebyl potřeba další souhlas klíčenky či MFA. Čeká se pouze na opakovaný přednes hlavní Aidou. Ranní automatická aktualizace podkladů ani načtení podrobných dokumentů tím nejsou implementované.

### První textové předání Aidou potvrzené

Miloš po opravě hosta 0.2.1 potvrdil, že Aida vypsala stručný ranní briefing. Společně s úspěšnou živou kalibrací, vytvořením briefingu z ověřeného kalendáře a přímým cloudovým čtením je tím doložený první průchod +4U → Iris Connect → připravený výstup Iris → omezené Iris Local → textová odpověď Aidy na tomto Macu. Plné znění její odpovědi ani přesný čas opakovaného volání nejsou součástí potvrzení; netvrdit samostatnou kontrolu všech vět.

Tento pilot je dokončený. Navazuje pravidelná aktualizace podkladů s řízeným MFA, příprava skutečných zdrojových dokumentů a samostatné ověření hlasového rozhovoru. Pracovní rezervace, rozhodovací zápisy, automatická rotace klíče a migrace na Mini nejsou tímto výsledkem dokončené ani nově spuštěné. Před skutečným ranním použitím obnovit večerní zdroje; po 30 minutách je nástroj výslovně označí jako stale.


## Automatizace první přípravy – nasazeno 18. října 2026

Na tomto Macu běží Connect 0.7.1, MCP server 0.3.0 v hostu 0.2.1 a soukromý worker trvalé pracovní fronty. Člověk dokončil nové souhlasy a přihlášení; fronta sama navázala na čekající sběr. Schválené kontrakty ManagementKit meeting/document/keyTask/request prošly živým pilotem. Elementary meeting dál selhává jako schemaMismatch a zůstává konkrétní otevřenou opravou, nikoli povoleným fallbackem.

Obsahová příprava a omezený výstup jsou zapojené: nový briefing pro 19. října obsahuje 14 karet, dvě zpracovaná rozhodnutí s pěti ověřenými citacemi a výslovně označené mezery. Skutečné čtení nového schématu uspělo místně i přes Iris Local. Celkový stav je partial. Trvalá fronta, čekání na MFA bez startu, duplicity, vazba analýzy na balíček a opravy čerstvé publikace jsou synteticky otestované.

Večerní příprava 18:00 a ranní obnova 7:00 Po–Pá jsou uložené aktivní automatizace tohoto chatu; tichý následný běh dokončuje pouze čekající analýzu. Miloš předal potvrzení hlavní Aidy o jediné odpovídající rutině s doručením do jejich chatu od 19. října. První skutečné plánované doručení, obnovení po další MFA a hlasový průchod ještě čekají na provozní ověření. [Runbook a přesný aktuální stav](briefing-runbook.md), [omezení zdrojů](briefing-automation.md). Rotace klíče, oprava Elementary adaptéru, další konektory a zápisy zůstávají samostatné navazující kroky.


## Dokončená oprava čtení Elementary – 18. října večer

0.7.7 opravuje dokumentovaný unsupportedKeyList (pilot odstraní jen odmítnuté aliasy oid/bid) a převod RichText.Block uu5String/uu5string polí. Po lidském obnovení souhlasů a MFA prošel pilot i běžná dávka; kontrolní Meetings AI records tool vrátil skutečnou přípravu. Dočasná diagnostická výjimka je vyčerpaná a export odstraněný. Prošlo 68 nativních syntetických testů.

Aktuální pondělní briefing byl znovu obsahově posouzený a publikovaný: 14 karet, pět analýz, sedm ověřených citací, current/partial. Skutečné místní i cloudové MCP čtení uspělo. Neúplný vložený obsah a přílohy zůstávají označené; další kvalita těchto převodů je navazující práce. První plánované doručení hlavní Aidou a hlas ještě nemají provozní důkaz. Podrobné výsledky jsou v iris-connect-read-verification.md; k dokončené opravě už není potřeba další nativní nasazení nebo místní souhlas.


## Uživatelsky potvrzený hlasový průchod – 18. října večer

Miloš v tomto chatu přímo potvrdil: „Vyzkoušel jsem to, pobavil jsem se o zítřejších schůzkách.“ Hlasový rozhovor s Aidou nad zítřejší agendou je tím uživatelsky potvrzený. Není to samostatný rozbor správnosti všech vět, důkaz trvalého uložení rozhodnutí do Iris ani důkaz plánovaného ranního doručení. To dál ověřuje první ranní provozní test 19. října.
