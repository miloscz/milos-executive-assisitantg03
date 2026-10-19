# Inventura původní Iris – 18. října 2026

Inventura je čtecí. Původní projekt `/Users/milosvodrazka/Personal/milos_executive_assistant` nebyl upraven, jeho procesy nebyly vypnuté. Přihlašovací implementace, klíčenky, tokenové soubory, prostředí, logy, surový Signal archiv a nahrávky nebyly zdrojem obsahové inventury. Binární soubory jsou zahrnuté pouze do počtů. Nejde o audit všech běžících služeb ani kontrolu správnosti každého článku.

Agregovaný snímek: [inventurní data](legacy-inventory-2026-10-18.json). Opakovatelný nástroj: [inventory-legacy.py](../tools/migration/inventory-legacy.py). Nástroj prochází jen vyjmenované části pracovního vaultu, nevrací texty, názvy úkolů, osoby nebo URL. Čas v JSON je čas prohlídky, nikoli poslední synchronizace +4U. Neprochází skryté adresáře ani symbolické odkazy. Obsahově prohlédnuté pracovní postupy a tři vybrané související poznámky jsou popsané níže.

## Rozsah a použitelnost

Ve vyjmenovaných oblastech je **1 154 neprázdných Markdown souborů** do 1 MiB. Nejde o počet ověřených znalostí ani unikátních entit.

| Oblast původního vaultu | Nález | Převod |
| --- | --- | --- |
| `meetings/` | 279 poznámek, 140 označených `stub: true`; 276 mají frontmatter a pole zdroje. | Historie schůzek se zachováním data a přesné instance. Stub není podklad ani důkaz chybějícího zápisu v dnešním systému. |
| `people/`, `orgs/`, `products/` | 123 osob, 11 organizací, 5 produktových poznámek. V těchto třech oblastech žádná nemá frontmatter `source`/`source_url`. | Sjednotit identity, aliasy a zdroj ke konkrétním tvrzením. Odkazy a citace mohou být v těle; absence pole neznamená absenci všech zdrojů. |
| `projects/` | 40 Markdown souborů, 23 s frontmatter. Nejde o 40 projektů. | Oddělit popis projektu, pracovní rozpracovanost a platné procesní know-how. |
| `topics/`, `decisions/` | 13 témat, 22 záznamů rozhodnutí. Vybraný záznam o lokálních přepisech výslovně říká DRAFT. | Kandidáty nepovýšit na potvrzená rozhodnutí. Zachovat autora návrhu, zdroj a ověření člověkem. |
| `messages/` | 564 kurátorovaných digestů. | Druhotný historický zdroj: oddělit citované sdělení od interpretace původní Iris. Neobnovovat ze všech digestů úkoly. |
| `tasks/` | 8 pracovních seznamů; statistika níže. | Historické pohledy a kandidáti, nikoli počáteční autoritativní pracovní databáze. |
| `journal/`, `reports/` | 34 deníků, 22 Markdown reportů; navíc audia a textové souhrny. | Historický kontext, ne nezávislé potvrzení reality. Audia se nepřenášejí. |
| Strategie, výroba, management, šablony, `me/` | Další doménové poznámky, tabulky a dokumenty. | Pozdější výběrová migrace po oblastech; žádný plošný import. |
| `product/` vedle `products/` | Samostatná další poznámka mimo obvyklé umístění. | Výjimku vyřešit identitou při migraci; neslučovat naslepo podle názvu. |

Spravovaná KB přes instalovanou dovednost `knowledge-base:kb` nevrátila při `list --tier PERSONAL` žádná témata (`{}`). Toto není důkaz, že jiné KB nebo jiné vrstvy neexistují. Původní vault není touto CLI automaticky spravovaný. Pilot nezakládá druhou kopii pracovních znalostí do obecné sdílené UAF vrstvy.

## Inbox: doložená příčina problému

| Seznam | Otevřené checkbox řádky | Zaškrtnuté řádky |
| --- | ---: | ---: |
| inbox | 1 735 | 2 |
| next-actions | 31 | 0 |
| waiting-for | 44 | 0 |
| week | 17 | 0 |
| done-log | 0 | 65 |

Počty se nesčítají do unikátních závazků: stejné téma může být ve více seznamech a jeden řádek může zastupovat více aktivit. Registr opakování a index key tasks nepoužívají checkbox jako jednotku evidence.

Otevřené řádky inboxu podle vzájemně výlučné jednoduché klasifikace: **1 203 Signal (69,3 %)**, **386 s URL +4U/Unicorn (22,2 %)**, **146 jiné nebo bez takové značky**. URL +4U sama neprokazuje existenci vlastního úkolu: může odkazovat na schůzku nebo dokument. Pouze 466 řádků má `@due`, 171 má `@owner`. Jde o výskyt značek, nikoli kontrolu správnosti termínu či vlastníka. Absence přesně stejných řádků nevylučuje významové duplicity.

Konkrétní pravidla původních postupů problém vysvětlují:

| Původní postup | Pozorované chování | Změna v nové Iris |
| --- | --- | --- |
| `CLAUDE.md`, Task OS | Interaktivní přidání vyžaduje potvrzení, ale headless procesy mohou dál samy plnit inbox. | Jednotný filtr pro každý zdroj a každou roli. |
| `signal-sync/SKILL.md` | Úkoly i kandidáti rozhodnutí do inboxu; nejasnosti také; nad limit 15 digestů další řádek za konverzaci. | Obohacení existující práce, návrhy do samostatné fronty, přetečení do provozní evidence. |
| `meeting-sync/SKILL.md` | Detekované úkoly/rozhodnutí, staré stubs i přetečení nad 15 poznámek do inboxu. | Příprava pod schůzku; chybějící zdroj jako stav podkladů; provozní limit není osobní úkol. |
| `meeting-minutes/SKILL.md` | Vlastní detekované akce do inboxu. | Nejprve identita existující aktivity; jinak návrh se zdrojem, nikoli automatický závazek. |
| `task-sync/SKILL.md` | Nové +4U záznamy do inboxu; seskupování i podle názvu/termínu; uzavírání i podle nepřítomnosti. | Stabilní ID vlastní elementární aktivity; absence ve výpisu nikdy neuzavírá práci. Převzít správné rozlišení Milošovy části od celého úkolu. |
| `task-triage`, týdenní plánování/review | Přesuny mezi textovými seznamy, ruční úpravy, Git zápisy jednotlivými procesy. | Generované pohledy nad jednou evidencí; jeden zapisující správce a historie změn. |

Toto je nález z instrukcí a existujících dat, ne důkaz, že každý uvedený proces právě běží. Převzetí zapisování musí předem zjistit skutečně aktivní procesy a přepnout vždy jednoho vlastníka. Pouhé nasazení nového filtru starý inbox nevyčistí ani nezastaví jeho plnění.

## Co zachovat a co nepřenášet

Zachovat kontextový balíček před prací, poznámky s odkazy na zdroje, sledování vlastních elementárních aktivit, rozlišení kandidáta rozhodnutí, historii interakcí, opakované povinnosti, šablony přípravy a kritéria skutečného dokončení. Znalostní, schůzková a úkolová role navrhují změny; zapisuje služba.

Nepřenášet instrukce „všechno nejdřív do inboxu“, uzavírání podle absence, slučování podle názvu, tvrzení „hotovo“ bez ověření a samostatné Git zápisy každého agenta. Staré přihlašovací postupy nejsou zdrojem nové KB. Surové archivy, média, logy a přístupové konfigurace nejsou obsahem tohoto pilotu.

Další krok je [omezený pilot pracovní evidence, KB a vstupního filtru](work-knowledge-pilot.md). Ostatní skills a domény mají zatím jen seznam kandidátů; jejich bezpečnost a vhodnost nejsou touto inventurou certifikované.
