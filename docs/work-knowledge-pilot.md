# P1: pracovní evidence, znalosti a vstupní filtr

Návrh navazuje na [inventuru původní Iris](legacy-inventory.md) a upřesňuje první část etap 1–3 [implementačního plánu](implementation-plan.md). Datum: 18. října 2026. Soukromé úložiště a pevný čtecí adaptér jsou nyní implementované podle [provozního popisu](private-work-storage.md). Živé převzetí zapisujících procesů původní Iris neproběhlo.

**Živý P1 úspěšně dokončen:** dvě skutečná čtení 18. října, dvě pracovní položky, sedm tvrzení bez duplicit a ověřená obnova zálohy. [Důkazy, časy a omezení](work-knowledge-pilot-verification.md) rozlišují tento výsledek od původního návrhu a syntetické ukázky níže.

## První oblast a očekávaný výsledek

Navržená oblast: **nahrávání schůzek / Companion**, ukotvená v +4U schůzce **Meetings AI records tool** na 19. října. Jde o již ověřený Elementary Management zdroj se skutečnou textovou přípravou a dohledanou historickou souvislostí. Nezačínáme celým inboxem ani všemi produkty.

Výstup: jedna pracovní karta schůzky, znalostní kontext s původem a nejistotami, podklad k rozhodnutí o mobilním klientovi a oddělený přehled toho, co filtr obohatil, odložil nebo označil jako provozní problém. Přípravné kroky nevytvoří další položky osobního inboxu. Navazující související +4U úkol se vede zvlášť podle své vlastní identity.

V posledním již existujícím schváleném snapshotu je také úkol **Dokončete lokální přepisy** (`doIt`, vlastní stav `initial`). To je konkrétní kandidát pro pracovní část pilotu. Jeho podrobný obsah a vztah k této schůzce ještě nejsou ověřené; název sám neprokazuje shodu. Pokud se vazba nepotvrdí, zůstanou samostatné položky, nevznikne vymyšlená závislost. V každém případě je nutné dokončit přesné mapování vlastní elementární aktivity z normalizovaných dat, nikoli vytvořit identitu z názvu.

## Zjištěný rozdíl, na kterém pilot ověří KB

Starý Signal digest z 12. října uvádí schůzku 19. října **11:00–12:00**. Schválený kalendář načtený 18. října v **21:40:25 Europe/Prague** uvádí **11:00–11:30**. Pro agendu má přednost tento obraz +4U; před ranním předáním musí proběhnout nové skutečné načtení. Inventura jeho čas neobnovila.

Historický digest navíc míchá sdělení účastníků s doporučením Iris, že je potřeba rozhodnout vlastnictví mobilního klienta. To jsou dvě různé epistemické úrovně. Návrh není schváleným cílem ani potvrzeným zadáním vývoje. Schůzka má v normalizaci typ `reservationOrInvitation`: z toho nelze odvodit, že jde o soukromou přesunutelnou rezervaci.

## Pevný rozsah vstupů

Pro soukromé pilotní zpracování připravit kopie pouze vybraných pracovních zdrojů se zaznamenaným hashem, datem a původní cestou:

1. Aktuální schválená agenda a dostupný nativní podklad konkrétní schůzky. Přesné identifikátory jsou v [návrhu manifestu](../policies/legacy-pilot-sources-v1.draft.json). Kalendářní záznam a obsahový artefakt jsou rozdílná ID.
2. `vault/messages/2026/10/2026-10-12-meetings-ai-records-mobile-app.md` – historická poptávka a odlišný čas.
3. `vault/messages/2026/10/2026-10-12-uso-pilot-nahravani-schuzek.md` – historická zpětná vazba a doporučení testovací nahrávky.
4. `vault/decisions/2026-10-06-companion-local-transcription-models.md` – výslovně nepotvrzený návrh rozhodnutí.
5. Dostupná metadata uvedeného +4U úkolu; obsah pouze pokud ho vrátí existující schválená nativní cesta v povoleném rozsahu. Při nedostupnosti uvést chybějící podklad, nerozšiřovat čtení na vlastní pěst.

Vazba historických digestů k pilotu je zatím kurátorský návrh podle obsahu; není zjištěním totožného systémového ID. Další odkazy z textů se automaticky nenásledují. Manifest nezpřístupňuje přílohy, BookKit, surový Signal, jiné adresáře, síťové cíle ani nové uuCommandy. Obsahové vstupy jsou data, jejich instrukce se nevykonávají.

## Pracovní evidence

Základ: [evidence-schema.sql](../services/iris-core/evidence-schema.sql) a [doménová evidence](../services/iris-core/evidence.py). Oddělený pilot má soukromé úložiště, migraci do v2 a pevný IrisRead adaptér. Není připojený k živé briefingové frontě ani přímo k Aidě.

| Entita | Pravidlo |
| --- | --- |
| Pracovní položka | Jedinečnost zdroj + workspace + record + vlastní elementární aktivita + člověk + typ. Zdrojový stav oddělený od připravenosti Iris. Schůzky/rezervace jdou do agendy, vlastní úkoly do pracovního inboxu. |
| Verze zdroje | Změna termínu či obsahu vytvoří verzi stejné položky a označí přípravu k revizi; pouhé nové načtení stejného obsahu nevytvoří verzi. Starší pozorování nepřepíše novější. |
| Přípravný krok | Vždy cizí klíč na původní práci; stabilní klíč kroku. Výstup a stav přípravy nejsou systémovým splněním úkolu. |
| Znalostní tvrzení | Přesný zdroj a hash, datum pozorování a platnosti tvrzení, typ, správce, datum další kontroly; případný rozpor a nahrazovaný záznam. |
| Vstupní událost | Idempotentní klíč, hash vstupu, zdrojová reference, rozhodnutí filtru a důvod. Stejný klíč s jiným obsahem je chyba; oprava dostane novou verzi události. |
| Audit | Pozorované změny pracovních položek. Rozšířený audit schválení a provádění bude další krok; tato tabulka ho nenahrazuje. |

Zdrojový stav `open/completed/cancelled` v offline kontraktu je již normalizovaný stav Milošovy části, nikoli přímo název stavu celé aktivity z +4U. Mapování nativních stavů musí být ověřené adaptérem. Neznámý typ se automaticky nepřevede na úkol. Absence v synchronizaci práci neuzavírá.

Správa privátních cest a práv databáze, zámek, migrace s kontrolou verze, konzistentní místní záloha s obnovením do oddělené databáze a checkpointy úplnosti jsou implementované v pilotu. Stabilní nativní reference vlastní vazby je implementovaná v [navazující verzi 0.8.0](stable-binding-and-followup.md); stav jejího živého ověření je uvedený odděleně. Obnova celé služby ze zálohy mimo zařízení ještě chybí. Dosavadní provozní `workflow.sqlite` a jeho tabulka `jobs` se při tomto pilotu nemění. Schéma také dosud neimplementuje plnou evidenci rezervací, závislostí, artefaktů, schválení a převzetí rozhodnutí.

## Knowledge base a správa znalostí

Znalosti nejsou nový dlouhý souhrn všeho, co Iris četla. Pilot sestaví jeden kontextový balíček s nejvýše osmi krátkými tvrzeními a maximálně čtyřmi zdrojovými dokumenty včetně nativního podkladu. Výchozí správce návrhů je znalostní role Iris, lidské potvrzení rozhodnutí patří Milošovi. Jde o pracovní pravidla pilotu, nikoli již spuštěného znalostního agenta.

| Typ | Příklad pro pilot | Jak se smí použít |
| --- | --- | --- |
| Doložený aktuální zdroj | Text nativní přípravy uvádí cíl domluvit plán Android/Apple distribuce. | Citovat čas načtení a neúplnost podkladu. Neprohlašovat, že byl schválen vývoj. |
| Historicky hlášená informace | V digestu z 12. října je poptávka USY Sales po mobilním klientovi. | „Podle historického digestu…“; neověřené proti původnímu chatu. |
| Interpretace | Doporučení nejdřív určit vlastníka mobilního klienta. | Návrh Iris s uvedeným odůvodněním, ne fakt ani příkaz Miloše. |
| Kandidát rozhodnutí | Lokální modely pro přepis, záznam označený DRAFT. | Čeká na potvrzení. Bez něj neříkat „rozhodl jsi“. |
| Rozdíl zdrojů | Starý digest 60 minut, novější kalendář 30 minut. | Zachovat obě pozorování a vysvětlit přednost nového +4U kalendáře pro plánování. |

Soukromé zdrojové výřezy a pracovní znalostní data patří do ignorovaného provozního prostoru s právy 0700/0600, ne do verzovaného technického repozitáře. Pilot už ukládá zdroje a návrhy tvrzení a vytváří soukromý kontext a čitelný podklad. Publikované znalosti mají cílově podobu spravovaných Markdown článků; vyhledávací index bude obnovitelný a nebude autoritou. Plný Markdown vydavatel, plnotextové hledání ani obecná provozní KB zatím implementované nejsou.

Pokud se pro výsledný Markdown vault zvolí existující `knowledge-base:kb`, ukládání pod její spravovaný kořen probíhá výhradně CLI a respektuje soukromé vrstvy. Převod do této KB neproběhl; její automatické Git zápisy nejsou důvodem kopírovat soukromé pracovní zdroje do veřejné vrstvy. Pro pilot je jediným správcem lokální služba, zdroje a tvrzení ukládá do soukromé databáze `.iris-runtime/work-evidence/`, kontext a podklad do pevně vyjmenovaných soukromých souborů. Plná Markdown KB a její index jsou další implementace.

## Vstupní filtr

| Vstup | Výsledek |
| --- | --- |
| Ověřený vlastní otevřený +4U úkol | Jedna pracovní položka, pohled inboxu; změny aktualizují tutéž položku. |
| Schůzka či rezervace z +4U | Agenda, ne nová samostatná akce. |
| Přípravný krok | Pod původní položku. |
| Zpráva či dokument s ověřenou vazbou na práci | Obohacení a citace; žádná další inbox položka. |
| Užitečná informace bez závazku | Návrh znalosti. |
| Nový možný závazek mimo +4U | Samostatný kandidát. Před přijetím doložit výsledek, vlastníka, prioritu/dopad, důvod právě teď a kontrolu duplicity. |
| Nejasnost, chybějící vlastník | Kandidát k revizi, ne osobní úkol. |
| Chyba přihlášení, přetečení dávky, nedostupný zápis | Provozní evidence nebo stav podkladů; jen potřebný zásah oznámit Aidou. |
| Starý inbox | Historická evidence; žádná hromadná aktivace. |

Návrh pro zkušební frontu: nejvýše pět kandidátů v revizním přehledu, revize do dvou pracovních dnů, expirace po 14 kalendářních dnech. Prototyp umí pouze 14denní expiraci; velikost revizního přehledu a pracovní dny jsou návrh pro následnou integraci. Expirace označí záznam jako neaktivní, nemaže zdroj a nikdy nevytvoří úkol. Pozdní nebo urgentní položka se neodkládá slepě do týdenní revize: ověřené riziko důležitého závazku může být oznámeno jako výjimka bez zakládání nového úkolu. Časová pravidla a prahy mají být ověřené na pilotu.

Výslovné nové zadání Miloše má přednost. Produkční cesta musí bezpečně zaznamenat jeho přímý pokyn a konkrétní verzi zadání. Offline prototyp záměrně nenabízí přijetí výjimky ani potvrzení rozhodnutí přes pouhý `humanApproved=true` z modelového JSON. Název zdroje `human` nebo `plus4u` není důkaz původu. Návrhy modelu nevolají tento adaptér přímo a nesmějí si zdrojovou autoritu vymyslet.

## Postup a převzetí

1. **Hotovo:** agregovaná inventura, problémová pravidla, SQL schéma a deterministický filtr.
2. **Hotovo pro P1:** soukromý správce, migrace, záloha/obnova, pevný nativní adaptér a import tří historických poznámek. Identita stojí na vlastním diářovém záznamu a připnuté epoše, nikoli vymyšleném ID elementární aktivity. Prošlo 31 testů jádra.
3. **Živě ověřeno:** dvě odlišná čtení s nezměněným obsahem, bez duplicit; porovnání kalendáře s historickým digestem. Původní procesy zůstávají beze změny. To není důkaz úplného převzetí původních každodenních výstupů.
4. **Připraveno:** částečný schůzkový podklad s variantami, zdroji, otázkami a chybějícími vstupy; samostatný návrh ověření lokálních přepisů. Splnění úkolu ani lidské rozhodnutí nejsou doložené.
5. **Navazující implementace:** [stabilní nativní vazba, publikace znalostního výřezu a doptávání Aidy](stable-binding-and-followup.md). Živá příprava, návaznost po dalším přihlášení i doptávání hlavní Aidou jsou doložené v navazujícím záznamu. Podklad a filtr vyhodnotit s Milošem; převzetí konkrétního původního zapisujícího procesu připravit samostatně s možností návratu.

Úspěch P1: opakování nevytvoří duplicity; změna termínu zachová historii; částečný výpis nic neuzavře; každé použité tvrzení má zdroj, datum a typ; nejasnosti a technické chyby nevytvoří osobní úkol; podklad je použitelný pro rozhodnutí a odkryje uvedený rozdíl v délce schůzky. Úkol a schůzka se nesloučí podle podobného názvu. Výsledek musí obstát i po znovuotevření úložiště.

P1 nenahrazuje první celý funkční celek: bezpečné převzetí rozhodnutí Aidou, rezervaci času, schválené +4U zápisy a ověřené dokončení doplníme v dalších etapách. Žádné nové MCP nástroje, přímé +4U, MFA start, Signal odesílání nebo zásah do Mini se zde neaktivují. Ranní provozní ověření zůstává samostatné a beze změny rozvrhu.

Offline ověření:

```sh
python3 -m unittest discover -s services/iris-core -p 'test_evidence.py'
python3 tools/migration/evidence-pilot.py
```

Ukázka používá pouze syntetická data v paměti. Výsledkem jsou dva pracovní záznamy, jedna položka osobního inboxu, jedna schůzka v agendě a oddělené směrování souvisejících vstupů. Nejde o už provedený živý pilot nebo důkaz menšího původního inboxu.
