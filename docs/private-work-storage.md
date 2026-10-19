# Soukromé úložiště a připojení pracovní evidence

Implementace místního pilotu z 18. října 2026. [Vymezení P1](work-knowledge-pilot.md), [schválené vstupy a kontroly](../policies/legacy-pilot-sources-v1.approval.json). Původní Iris zůstává beze změny.

Aktuální aditivní rozšíření: [předávání práce přes Aidu](aida-work-handoff.md) přidalo schéma 3 s aida_requests a aida_receipts; pracovní položky, znalosti a dřívější verze se neměnily. Podrobnosti schématu 2 níže zachycují základ před tímto rozšířením.

## Úložiště

`services/iris-core/private_store.py` používá pouze pevný adresář `.iris-runtime/work-evidence/`. `.iris-runtime` je ignorovaný Gitem. Adresáře musí mít práva 0700, soubory 0600 a patřit aktuálnímu uživateli. Existující nebezpečná práva se automaticky neopravují: operace je odmítnuta. Totéž platí pro symbolické odkazy, souborové hardlinky a nebezpečné SQLite journal/WAL/SHM soubory. Otevření kontroluje typ, vlastníka, práva a identitu inode; soukromé komponenty cest a historické vstupy se otevírají s `O_NOFOLLOW`.

Jediný zapisující proces drží neblokující souborový zámek. SQLite používá foreign keys, plnou synchronizaci a DELETE journal, aby zálohování nemuselo přenášet živé WAL. Import pracovních položek, zdrojových výřezů, znalostních návrhů a capture checkpointu probíhá v jedné transakci. Chyba zruší celý import; nepřítomnost ve výpisu neuzavírá práci.

Migrace `evidence.migrate` převede původní offline schéma do verze 2, kontroluje předchozí strukturu a odmítá neznámou novější verzi. Nevytváří souběžnou kopii `workflow.sqlite`; briefingová fronta zůstává oddělená. Nové tabulky evidují captures, zdrojové snapshoty a připnutou epochu nativního párování. Původní soubor `evidence-schema.sql` je základ migrace v1, původní provozní číslo této etapy bylo SQLite `user_version=2`; následné schéma 3 je popsané výše.

| Soukromý artefakt | Účel |
| --- | --- |
| `state.sqlite` | Práce a její verze, kroky přípravy, návrhy znalostí, směrování vstupů, zdrojové výřezy a čtecí checkpointy. |
| `backup.sqlite` | Konzistentní místní SQLite záloha vytvořená backup API. |
| `pilot-context.json` | Výběr tvrzení se zdroji, daty, citacemi, typem a omezeními. |
| `pilot-memo.json` | Rozhodovací návrh a pracovní kontrolní seznam; ne schválené rozhodnutí nebo dokončený úkol. |
| `pilot-memo.md` | Čitelná podoba téhož soukromého podkladu pro Miloše. |
| `pilot-report.json` | Časy zdrojů, počty, výsledek opakování a kontroly zálohy. |

JSON artefakty se publikují přes soukromý dočasný soubor a atomické přejmenování s fsync; názvy jsou pevně povolené. Neexistuje obecný CLI argument pro cestu či URL. Soukromá data nemají nový MCP nástroj a Aida nemůže číst databázi, snapshoty nebo tyto soubory. Její dosavadní pětinástrojové rozhraní ani sandbox se nemění.

Záloha se ověřuje `integrity_check`, kontrolou cizích klíčů a skutečným obnovením do oddělené databáze v paměti; porovnávají se všechny řádky všech tabulek. Živá databáze se při zkoušce nepřepisuje. Záloha leží na stejném disku: neřeší ztrátu počítače. Záloha mimo zařízení a obnova celé služby jsou další provozní krok. Práva souborů izolují jiné macOS účty; nejsou izolací před správcem/rootem nebo libovolným procesem téhož uživatele. Aida je proto oddělená omezeným MCP a sandboxem. Samotná SQLite databáze nemá vlastní šifrovací klíč; šifrování disku závisí na nastavení macOS. Tokeny a přístupové kódy do této vrstvy nepatří.

## Nativní čtecí cesta

`connect_evidence.py` používá pouze již existující podepsaný IrisRead prostřednictvím omezeného helperu `workflow.helper`. Před čtením i po něm ověřuje stav relace, nikoli přihlašovací UI. Po lidském přihlášení pevně ověří `diagnostics.calendarBoundaries` a `diagnostics.sources`, poté `tasks.listActive`, kalendář pro datum pilotu a `sources.prepare`. Uživatel v tomto chatu výslovně potvrdil obě kontroly; záznam je v approval JSON. Není obnovená jednorázová diagnostická výjimka pro export názvů varování.

Při chybějící relaci vrací `loginRequired`. Nemá cestu ke startu MFA, potvrzení upozornění nebo autentizačním údajům. Pro chybějící přihlášení se nevytváří osobní pracovní úkol. Čas načtení pochází z Iris Connect, nikoli z času importu. Cache hit zachovává skutečný `fetchedAt`; dvě spuštění nejsou automaticky dva odlišné síťové snímky. Neúplná nebo více než 30 minut stará agenda se do nového capture nepřijme. Neúplné textové podklady jsou přijatelné pouze s viditelným omezením, nikdy jako důkaz kompletní přípravy.

Do databáze přecházejí jen dvě pevné pracovní položky pilotu a jejich schválené přímé podklady; ostatní data vrácená omezeným helperem se neukládají. Tři historické soubory jsou explicitně povolené a omezené na 64 KiB. Odkazy uvnitř se nenásledují, instrukce z obsahu se nevykonávají. Obsah s rozpoznatelnými vzory přístupových údajů se odmítne místo uložení.

## Identita a současné omezení

Dosavadní normalizace exportuje vlastní `uuDwRecord.id` a `ownElementaryState`, nikoli samostatné ID elementární aktivity nebo identitu vlastního workspace. Adaptér tento údaj nevymýšlí. Používá `identityBasis=selfDiaryRecord`, ID vlastního záznamu, nativně potvrzeného self a soukromou epochu párování. Obsahový artefakt a diářový záznam mají oddělené identity. Vlastní elementární ID zůstává prázdné a tento fakt je uložený v evidenci.

P1 připínal epochu a při její změně bezpečně zastavil. Connect 0.8.0 nyní vystavuje stabilní neprůhlednou referenci ověřeného účtu a potvrzeného prostoru. Převod P1 vyžaduje dvě shodné ověřené vazby a zachovává interní ID i historii; jiná reference vyvolá `scopeReviewRequired`. Přesný postup a stav živého ověření jsou v [návaznosti evidence](stable-binding-and-followup.md). Stále jde o dvě pilotní položky, nikoli hotovou migraci všech úkolů.

Stav úkolu se určuje z vlastní části (`initial/replanned/reactivated/attention/warning` otevřené, známé odpovězené stavy odděleně), nikoli ze stavu celé aktivity. Neznámý stav, změněná identita schůzky nebo chybějící vybraný záznam zastaví capture. Schůzka není prohlášená za soukromou přesunutelnou rezervaci. Souvislost úkolu lokálních přepisů a schůzky je tematická; není vytvořená nepotvrzená závislost.

## Spuštění a rozsah

```sh
python3 -E -s services/iris-core/recording_pilot.py run
python3 -E -s services/iris-core/recording_pilot.py status
python3 -m unittest discover -s services/iris-core -p 'test_*.py'
```

`run` provede dvě čtení přes omezeného nativního klienta, import do soukromé evidence, kontext, podklad a kontrolu zálohy. Standardní výstup obsahuje pouze stavy, počty a časy. Výjimky nevracejí surové odpovědi ani libovolné chybové texty. `status` čte jen metadata pilotního úložiště. CLI není součástí Aidina MCP.

Tato změna nepřidává automatizaci nebo LaunchAgent, nepřebírá zapisující procesy původní Iris, nepřepisuje briefing pro Aidu a nemění ranní rozvrh. Obsah pilotního podkladu nejprve vyhodnotíme; jeho publikace Aidě se musí napojit na stávající validátor citací a schéma briefingu. Plná Markdown KB, vyhledávání, trvalé lidské rozhodnutí a rezervace času zůstávají další implementace.
