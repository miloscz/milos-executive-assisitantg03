# První příprava ranního briefingu

Lokální Python služba čte pracovní data výhradně přes podepsaný IrisRead. Nemá autentizační kód, přístup ke klíčence, HTTP klienta ani schopnost vyvolat MFA. Neprovádí zápisy do +4U nebo inboxu.

```sh
python3 services/iris-core/briefing.py refresh --date 2026-10-19
```

`refresh` načte aktivní DW bez časového filtru a ověřený kalendář zvoleného dne. Dokud kalendářní kontrakt není aktivovaný, briefing použije jen známé bloky z aktivních DW a označí kalendář `activeRecordsOnly`. Takový výsledek neposkytuje potvrzenou dostupnost. `build` vytvoří náhled ze soukromého již načteného aktivního snapshotu bez dalšího síťového čtení.

Provozní JSON soubory patří výhradně do ignorovaného `.iris-runtime/`, adresář má práva 0700 a soubory 0600. Jediný publikovaný výstup je `morning-briefing.json`. Zdrojové snapshoty nejsou dostupné procesu MCP. Compiler publikuje nejvýše 24 bloků, tři prioritní položky a osm souběhů; případné zkrácení je označené. Výběr priorit vychází z doloženého typu a vlastního otevřeného stavu, návaznosti na časový blok a termínu v posledním týdnu či cílovém dni. Pozvánky, rezervace, chatové záznamy a neznámé vlastní stavy se automaticky nemění na nové úkoly.

První podklady k rozhodnutí obsahují explicitní další krok a chybějící informace. Nejsou vydávány za analýzu dokumentu, který nebyl načtený. Odkazy jsou jen zdroje pro člověka; služba je automaticky neotevírá. Bez znalosti účastníků se žádná položka nepovažuje za přesunutelnou vlastní rezervaci.

MCP nástroj `iris_get_morning_briefing` nemá parametry a vrací pouze přísně ověřený připravený výstup. Po 30 minutách od nejstaršího použitého zdroje je označený `stale`; Aida musí uvést datum a stáří, zejména u náhledu sestaveného předchozí večer. Čtení briefingu nevyvolá nové načtení ani MFA. Před ranním použitím je nutné explicitně obnovit podklady v platné spárované relaci. Pravidelný scheduler, push události, plná znalostní příprava a rozhodovací zápisy zatím implementované nejsou.

## Ověření

```sh
python3 -m unittest discover -s services/iris-core -p 'test_*.py'
node services/iris-mcp/scripts/briefing-smoke.mjs
```

Unit testy jsou syntetické. Smoke čte jen již připravený briefing skutečným sandboxovaným MCP a vypisuje pevná metadata, ne přihlašovací údaje.

## První živý výsledek

18. října 2026 po úspěšné kalibraci Connect 0.6.2 vznikl briefing na pondělí 19. října s ověřeným kalendářem: 11 bloků, tři priority, dva konflikty. Přečtení přes skutečné omezené stdio MCP uspělo s coverage=verified a freshness=current. Nejstarší zdroj byl načten v 19:17:13 Europe/Prague; jde o večerní přípravu, kterou je před ranním použitím nutné aktualizovat. Nejde o načtené detailní podklady nebo již uskutečněná rozhodnutí. Doručení hlavní Aidou se ověřuje zvlášť.
