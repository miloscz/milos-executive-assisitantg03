# Příprava a ranní aktualizace briefingu

**Pracovní předání MCP 0.5.0:** `work_requests.py` a úzký UNIX bridge přidávají trvalé dopracování a dvoufázový záznam rozhodnutí. Schéma evidence 3, 42 testů jádra. Obsluhu bridge zahajuje stávající worker; modelový krok přijatých lidských dopracování je samostatný; průběžný heartbeat je na notebooku pozastaven. [Rozsah, testy a nasazení](../../docs/aida-work-handoff.md).

**Aktuální napojení:** večerní i ranní workflow používá stabilní nativní vazbu, soukromou pracovní evidenci a kurátorovanou znalostní přípravu Companion. Karty procházejí validací citací a vedle briefingu vzniká omezený detail pro doptávání Aidy. Prošlo 35 testů jádra. [Rozsah, bezpečnost a živé ověření](../../docs/stable-binding-and-followup.md). Historické počty a výsledky níže popisují dřívější stavy.

Samostatný offline základ pracovní evidence, návrhů znalostí a vstupního filtru je v `evidence.py` a `evidence-schema.sql`. [Pilot P1 a jeho omezení](../../docs/work-knowledge-pilot.md) rozlišují tento prototyp od živého briefingového workflow níže. Prototyp nečte +4U, nevolá helpery ani MCP a nemění provozní databázi. Syntetický průchod: `python3 tools/migration/evidence-pilot.py` z kořene projektu.

Navazující `private_store.py`, `connect_evidence.py` a `recording_pilot.py` přidávají [soukromou databázi a pevný nativní čtecí adaptér](../../docs/private-work-storage.md). Pilot zpracovává dvě vybrané pracovní položky a tři historické poznámky, vše pod `.iris-runtime/work-evidence/`; nemá přístup k přihlašovacím údajům a není vystavený přes MCP. Spuštění: `python3 -E -s services/iris-core/recording_pilot.py run`. Změna epochy párování vyžaduje revizi rozsahu. Ranní workflow a původní Iris toto spuštění nepřebírá.

Iris běží na tomto Macu. Pracovní jádro získává agendu a schválené podklady pouze přes podepsaný IrisRead. Nemá HTTP klienta, autentizační kód, klíčenku ani schopnost vyvolat MFA. Aida čte pouze publikovaný výstup přes Iris Local; nedostává zdrojové snapshoty ani přístup k počítači.

Provozní vstup je `workflow.py`, nikoli původní diagnostický `briefing.py build/refresh`:

```sh
/usr/bin/python3 -E -s services/iris-core/workflow.py run --phase prepare
/usr/bin/python3 -E -s services/iris-core/workflow.py run --phase morning
/usr/bin/python3 -E -s services/iris-core/workflow.py status
```

Trvalá soukromá fronta ukládá fázi + datum a checkpoint v SQLite. Zámek brání duplicitní práci. Večer míří na příští pracovní den, v pátek na pondělí; ranní běh na dnešek. Příprava vybírá tři vlastní priority a aktuální schůzky z ověřeného kalendáře. Pozvánky ani rezervace se samy nestávají úkoly. Zápisy, rezervace času a schvalování nejsou součástí této služby.

Při chybějící relaci vznikne skutečná potřeba přístupu, ale jádro smí jen IrisControl status a prepare. Upozornění a nový přímý lidský pokyn řeší hlavní Aida. Soukromý LaunchAgent fronty po dokončeném MFA obnoví existující čtení; nevytváří nové dny. Registrovanou ranní/večerní dávku dokončí přes omezený analysis_engine.py i po pozdním MFA; při čekání nebo idle model nespouští. Při neúspěchu místního párování čeká, místo aby použil jiný konektor.

Po načtení vznikne normalizovaný balíček a omezený analytický vstup. Model v tomto chatu zpracuje konkrétní podklady podle [runbooku](../../docs/briefing-runbook.md) a pevný publish ověří hash balíčku, skutečné citace, vazbu na položku a stáří. Staré citace se nepřenášejí na změněná data. Obsahově stejný ranní balíček může použít dříve ověřenou analýzu; nové časy vzniknou jen skutečným čtením. Publikace rozlišuje kontext, načtené zdroje a provedenou analýzu. Neúplnost zůstává viditelná i u zpracované karty.

Soukromé soubory a databáze v ignorovaném `.iris-runtime/` mají adresář 0700 a soubory 0600. MCP smí číst jen `morning-briefing.json` do 24 KiB a pevný publikovaný `briefing-details.json` do 64 KiB. Databáze a zdrojové snapshoty jsou nepřístupné. Briefing má nejvýše 24 bloků, 3 priority, 8 souběhů a 14 karet; detail musí odpovídat témuž briefingu. Datum a čas zdrojů jsou skutečné; po 30 minutách jsou stale. Čtení nic neobnovuje, nevyvolává MFA a nevykonává pokyny z dokumentů.

## Rozvrh a ověření

Aktivní heartbeat běhy tohoto chatu připravují agendu Po–Pá v 18:00 a obnovují ji v 6:40 pro předání Aidou v 7:00 místního pražského času. Třetí tichý běh dokončuje pouze již čekající analýzu po MFA: v 6:45, 6:50, 6:55 a dále po 15 minutách od 7:00 do 21:45. Vyžadují zapnutý otevřený Mac na nabíječce, přihlášené macOS a dostupnou aplikaci Codex. Samostatný uživatelský proces brání nečinnému uspání pouze při AC; obrazovku lze zamknout. Aida podle uživatelem předaného potvrzení uložila jednu odpovídající rutinu do hlavního chatu; první skutečné plánované doručení 19. října ještě čeká.

```sh
python3 -m unittest discover -s services/iris-core -p 'test_*.py'
node services/iris-mcp/scripts/briefing-smoke.mjs
```

Deset syntetických testů jádra ověřuje mimo jiné páteční a pražské datum, čekání na MFA bez startu, trvalost fronty, souběh, odmítnutí nepravé citace, vazbu analýzy na balíček a odmítnutí zastaralé publikace. Živý nový briefing na 19. října prošel přes skutečné stdio i cloudové Iris Local: 14 karet, dvě analýzy, pět citací, kalendář verified a celkový stav partial. Nativní dávka načetla 9 podkladů / 19 stránek. Elementary meeting stále neprošel kontraktem; přílohy a nepodporované vložené komponenty zůstávají chybějící. [Podrobnosti a otevřené opravy](../../docs/briefing-automation.md).

## První živý výsledek

18. října 2026 po úspěšné kalibraci Connect 0.6.2 vznikl briefing na pondělí 19. října s ověřeným kalendářem: 11 bloků, tři priority, dva konflikty. Přečtení přes skutečné omezené stdio MCP uspělo s coverage=verified a freshness=current. Nejstarší zdroj byl načten v 19:17:13 Europe/Prague; jde o večerní přípravu, kterou je před ranním použitím nutné aktualizovat. Nejde o načtené detailní podklady nebo již uskutečněná rozhodnutí. Miloš následně potvrdil, že hlavní Aida po opravě hosta 0.2.1 vypsala stručný ranní briefing. Textové předání je tím uživatelsky potvrzené; hlasový hovor ani úplnost konkrétního znění tohoto přednesu se tím neověřovaly.

Automatické obsahové dokončení ranní/večerní dávky, izolace CLI, limity a chybové stavy: [runbook](../../docs/briefing-runbook.md#automatické-dokončení-dávky-po-mfa--19-října). Průběžné agentní kontroly zůstávají vypnuté.

Přenos skutečných podkladů byl schválený souhlasem iris-content-runtime-v1. Miloš následně výslovně zadal přepnutí na gpt-6.1-sol/high; aktivní je přesný kontrakt iris-content-runtime-v2. Kontroluje se jeho hash, model i reasoning; při nesouladu analysisApprovalRequired. Místní oficiální CLI je aktualizované na 0.163.0. Obnova čtení a opětovné použití shodné ověřené analýzy jsou zachovány, automatický fallback na jiný model není nastavený.
