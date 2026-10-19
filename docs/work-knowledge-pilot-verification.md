# P1: živé ověření pracovní evidence a znalostí

18. října 2026, tento Mac. Pilot skončil úspěšně v **22:42:24 Europe/Prague**. Jde o čtecí provoz vedle původní Iris, nikoli převzetí jejích zapisujících procesů. [Rozsah P1](work-knowledge-pilot.md), [úložiště a omezení](private-work-storage.md).

## Skutečný průběh

Miloš po vypršení relace spustil přihlášení přímo v Iris Connect. Omezený stavový helper potvrdil platnou relaci. Agent nečetl přihlašovací UI, kódy ani tokeny a žádný pokus sám nezahájil. Kalendář v nové relaci správně odmítl provozní čtení bez ověření kontraktu; před jeho dokončením nevznikl úspěšný import.

Automatická kontrola schvalování dvakrát odmítla `diagnostics.calendarBoundaries` a `diagnostics.sources`. Akce se neobešla jinou cestou. Miloš následně výslovně odpověděl „Schvaluji obě čtecí kontroly“. Souhlas je v [approval JSON](../policies/legacy-pilot-sources-v1.approval.json); nativní politiky a bundle zůstaly nezměněné. Jednorázový export názvů varování se neobnovil.

Po pevných kontrolách běžely dvě dávky přes podepsaný IrisRead: `tasks.listActive`, kalendář pro 19. října a `sources.prepare`. Do soukromé databáze přešly pouze dvě vybrané položky. Tři historické poznámky byly načtené pouze pro čtení; následná kontrola potvrdila shodu jejich hashů s importovanými zdroji.

| Průchod | Úkoly načtené | Kalendář načtený | Dokončení zdrojové dávky |
| --- | --- | --- | --- |
| První | 22:31:33 | 22:31:59 | 22:36:59 |
| Druhý | 22:37:21 | 22:37:24 | 22:42:24 |

Vše 18. října, Europe/Prague. Nejde o příslib aktuálnosti ráno. Jsou to dvě odlišná pozorování, nikoli dva importy jednoho souboru. Nativní konzistence zůstává bestEffort, ne atomický serverový snapshot. Obsah vybraných položek a přímých podkladů byl mezi dávkami shodný.

## Výsledky

| Kontrola | Živý výsledek |
| --- | --- |
| Práce | 2 položky: Meetings AI records tool a Dokončete lokální přepisy. |
| Opakování | 2 captures, 2 pracovní verze celkem. Druhé čtení nevytvořilo kopie položek ani znalostí. |
| Příprava | 2 kroky, každý pod vlastní rodičovskou položkou. |
| Nový pracovní inbox | 1 vlastní +4U úkol. Původní inbox se neupravoval. |
| Agenda | 1 schůzka, bez tvrzení, že jde o soukromou přesunutelnou rezervaci. |
| Znalosti | 7 tvrzení se zdrojem, hashem, datem, správcem a typem. |
| Filtr | 1 agenda, 1 inbox, 1 obohacení, 1 znalostní vstup, 1 návrh k revizi. Žádný historický digest nevytvořil osobní úkol. |
| Rozhodnutí | DRAFT zůstal kandidátem; žádné lidské rozhodnutí se nepotvrdilo. |
| Rozdíl zdrojů | Kalendář 11:00–11:30, historický digest 11:00–12:00. Oba údaje mají původ; agenda vychází z kalendáře. |
| Soukromí | Ověřeno 0700 pro soukromé adresáře a 0600 pro všechny soubory, žádné symlinky mezi artefakty. |
| Obnova | Integrity a foreign-key kontroly prošly. Záloha byla obnovena do oddělené databáze; všechny řádky odpovídaly. Znovu ověřeno po vytvoření čitelného podkladu. |

31 syntetických testů jádra prošlo: nebezpečné cesty a práva, hardlinky a symlinky, souběh, migrace v1→v2, odmítnutí novějšího schématu, zrušení celého importu při chybě, vlastní stav úkolu, nepřítomnost bez uzavření, změna termínu, změna epochy, odmítnutí vzorů přístupových údajů a zákaz MFA startu v adaptéru. Tyto testy nenahrazují živý důkaz výše.

## Výstup a omezení

Čitelný soukromý podklad je `.iris-runtime/work-evidence/pilot-memo.md`; strukturovaný podklad, kontext a report jsou vedle něj. Nejsou v Gitu ani v novém MCP nástroji. Obsahují cíl schůzky, varianty mobilního řešení, návrh Iris, otázky k vlastnictví/kapacitě/rozsahu, chybějící vstupy a samostatný návrh ověření lokálních přepisů. Navržených 15 minut Milošova času před schůzkou není rezervovaných.

Příprava zůstává **částečná**. Zdrojová dávka ani obsah schůzky se nevydávají za úplné. Digesty nejsou znovu ověřené proti původnímu Signalu a jejich komentáře nejsou fakta. Neprokázali jsme splnění úkolu nebo akceptaci kontrolního seznamu. Tematická souvislost úkolu a schůzky není potvrzená procesní závislost.

Nic se nezapsalo do +4U, neodeslala se zpráva, nevznikla rezervace, nezměnily se nástroje Aidy ani její publikovaný briefing a rozvrh. Původní Iris a Mini se neupravovaly.

P1 ověřil úložiště, čtecí napojení a vybrané znalosti/inbox v jednom párování. Před pravidelnou evidencí přes další přihlášení potřebujeme stabilní nativní referenci vlastní vazby; současné chování při změně epochy je zastavení `scopeReviewRequired`. Další obsahový krok je vyhodnotit podklad s Milošem a napojit vhodný výřez na stávající validovanou publikaci briefingu pro Aidu. Původní zapisující procesy se převezmou samostatně po výběrovém porovnání.


## Navazující verze 0.8.0

Výše je historický výsledek P1 v jednom párování. [Navazující živé ověření](stable-binding-and-followup.md) doložilo stabilní vazbu přes další přihlášení se zachováním ID a historie, integraci znalostí do přípravy i doptávání hlavní Aidou přes šestý omezený MCP nástroj. Původní Iris zůstává beze změny; není tím dokončená plná migrace ani převzetí rozhodnutí.
