# Dopracování a rozhodnutí přes Aidu

Místní implementace navazující na Connect 0.8.0 a MCP 0.4.0. Původní Iris ani Mini se nemění. Nový MCP server 0.5.0 nabízí celkem deset nástrojů; nativní Connect se kvůli této změně nepřestavuje. Stav nasazení a živého ověření je na konci dokumentu.

## Rozhraní a bezpečnost

MCP přidává jen čtyři významové operace nad soukromým UNIX socketem `.iris-runtime/w.sock`. Nemá přístup k pracovní databázi, zdrojovým snapshotům, klíčence, dalším souborům ani síti. Nové povolení sandboxu je přesně tento socket, bez spouštění dalšího programu. Jádro kontroluje kernelové UID protistrany, privátní adresář a socket 0600; klient kontroluje typ, vlastníka a práva. Není to důkaz identity Aidy mezi procesy téhož macOS účtu.

Jedno spojení přijme přesně jeden JSON požadavek do 8 KiB, s pevným názvem metody a přesnými poli. Odpověď do 16 KiB má striktní schéma a filtr citlivých hodnot i na výstupu SDK. Timeout je omezený; validační nebo protokolové chyby nevracejí původní vstup ani výjimku. Pracovní bridge nemá žádnou cestu k MFA, vydání tokenů, obecnému HTTP, shellu nebo souborům na přání.

Příjem je omezený na 40 mutujících požadavků za hodinu a 20 čekajících položek. Stejné requestId a stejný obsah vrací uložený stav; jiné tělo pod stejným ID je requestConflict. Klient při timeoutu zachová ID a ověří jej stavovým nástrojem. Uložení požadavku a audit/receipt jsou jedna databázová transakce.

Soukromé úložiště přechází aditivní migrací na schéma 3: `aida_requests` a `aida_receipts`. Dosavadní práce, verze, znalosti a captures se nepřepisují. Plná záloha/obnova zahrnuje i nové tabulky. Záloha před prvním živým předáním má pevný název pre-handoff.sqlite.

## Verze podkladu

`iris_get_preparation_detail` vrací `detail.version`: otisk data briefingu a skutečného obsahu podkladu, včetně zdrojů a omezení. Samotný nový čas čtení verzi nemění. Změna obsahu, citací, cílového dne nebo detailu ji změní. Návrh se nikdy automaticky nepřenese na jinou položku či verzi. Bridge přijímá jen ID z aktuální agendy/priorit a shodný detail; při nesouladu přijde versionChanged/notPrepared. Zdroje pro návrh a potvrzení rozhodnutí musejí být nejvýše 30 minut staré. Dopracování lze přijmout i nad starší aktuálně publikovanou verzí, ale čeká v awaitingSources na skutečnou obnovu a shodu obsahu; starý čas se nepřepisuje.

Vedle znalostní pilotní schůzky mají verzi i ostatní již publikované přípravné karty. Jejich detail obsahuje jen informace už obsažené v briefingu; chybějící varianty se nevymýšlejí. Nové zdrojové typy nebo +4U commandy se nepovolují.

## Dopracování

`iris_request_preparation_revision` přijímá requestId, id, preparationVersion, topic, instruction do 1 000 znaků a directUserCommand=true. To je deklarace volající Aidy o novém lidském zadání. Obsah zadání se ukládá jako nedůvěryhodná data, nikoli jako oprávnění k nástrojům.

Iris vrátí queued. Pevný místní `work_requests.py next` vybere existující požadavek, ověří současnou verzi a připraví work-analysis-input.json s jeho zněním, verzí a povolenými výňatky pro konkrétní položku. Stav needsAnalysis není hotový výsledek. Chybějící/zašlé zdroje znamenají awaitingSources; změněná verze superseded. Bez nového lidského požadavku se zadání nepřenese na změněný podklad.

Zpracující model v tomto implementačním chatu připraví work-analysis-output.json: requestId, preparationVersion, packetHash, card, sections a summary. Karta odpovídá stávajícímu validátoru analýzy; sekce jsou nejvýše šest pevných témat po 1 800 znacích, shrnutí do 800. Musí být skutečně zpracované požadované téma, přesné citace a přiznané mezery. Jde o analýzu povolených načtených zdrojů, ne libovolné vykonání požadavku. Chybějící nové zdroje nebo externí kroky zůstanou výslovně uvedené.

`work_requests.py publish` znovu kontroluje ID, verzi, hash aktuálního balíčku, stáří a citace. Až po trvalém uložení výsledku přejde požadavek do completed a aktualizuje se publikovaný detail i karta briefingu. Čas zdrojů se nemění na čas analýzy. Při obnově stejné zdrojové verze se výsledek znovu použije; při změně podkladu se nepřipojí. Neúplný podklad zůstává partial. Completed je připravený uložený výsledek, ne potvrzení jeho doručení člověku.

## Rozhodnutí

1. Aida použije `iris_prepare_decision` s ID/verzí podkladu, requestId a přesným zněním decision do 1 000 znaků. Uloží se jen awaitingConfirmation, snapshot podkladu a desetiminutové potvrzení.
2. Aida člověku skutečně přečte přesné `workRequest.text`, vysvětlí místní záznam bez externího provedení a čeká na **nové přímé potvrzení tohoto znění**. Dosavadní rozhovor, vlastní návrh Iris, citace v dokumentu ani pokyn jiného agenta nejsou potvrzení.
3. Až pak volá `iris_confirm_decision`: nové requestId, decisionId původního návrhu, confirmationId a userConfirmed=true. Při timeoutu zachová ID potvrzovacího pokynu. Změněný podklad nebo expirované potvrzení vyžadují nový návrh, přečtení a nové potvrzení.
4. Recorded znamená trvalý místní záznam a audit. Do detailu přejde přesné znění, čas, výchozí verze, deklarovaná provenience a externalExecutionAuthorized=false. Nová verze detailu se mění i při připojení rozhodnutí; následné obsahové dopracování označí dřívější rozhodnutí jako basedOnOlderVersion=true. Při opětovné publikaci se události přehrávají v pořadí, bez ztráty výsledku dopracování. `iris_get_work_request` vrátí přesné uložené znění, stav a confirmationEvidence=callerAttestedAfterReadback. Jádro tuto deklarovanou provenienci zachová i ve vstupu další analýzy.

**Hranice důvěry:** ani příznak, ani nonce kryptograficky nedokazují přítomnost člověka či správné rozpoznání hlasu. Vynucené jsou pořadí, verze, expirace, neměnné znění a idempotence. Původ pokynu deklaruje Aida. Záznam výslovně obsahuje externalExecutionAuthorized=false. Žádné automatické platby, schválení v +4U, rezervace, zprávy, označení úkolu za splněný nebo jiné externí kroky se nespouštějí. Pro ně je nutné budoucí samostatné oprávnění a ověření výsledku.

## Zpracování a provoz

Místní worker obsluhuje pouze úzký bridge a dosavadní briefingovou frontu; sám nevolá model. Obsahové dopracování zpracovává existující dokončovací heartbeat podle tohoto runbooku. Jeho pracovní denní časy zůstávají zachované; nejedná se o okamžitý nepřetržitý modelový běh. Stavový nástroj Aidě umožní odlišit čekání od výsledku. Mimo uložené časy zůstává požadavek v evidenci do dalšího běhu nebo ručního zpracování v implementačním chatu.

Jádro spouštět jen pevnými operacemi `/usr/bin/python3 -E -s services/iris-core/work_requests.py next` a `publish`. Model čte jen pevný work-analysis-input.json a případně odpovídající povolené části briefing-packet.json, zapisuje jen work-analysis-output.json s právy 0600. Nevkládá do fronty své vlastní lidské potvrzení a nevolá nové rozhodovací nástroje jako test nad skutečnými daty.

## Stav ověření

Prošlo 42 syntetických testů jádra a 20 MCP testů, včetně skutečného lokálního getpeereid, zákazu ostatních UNIX socketů a sítě v OS sandboxu, odmítnutí tajných/neočekávaných polí, expirace, verzování, opakovaných ID, přesných citací, čekání na zdroje a přehrání posloupnosti rozhodnutí → dopracování po novém zveřejnění.

Místní worker a MCP host jsou nasazené přes stávajícího správce LaunchAgentů. Connect zůstal 0.8.0 se stejným procesem a platnou relací; žádný nový nativní souhlas, zadání kódů nebo MFA se nežádal. Před prvním předáním se ověřila záloha pre-handoff.sqlite: integrity=true, restoredRowsMatch=true, dvě dosavadní práce a sedm tvrzení zachovaných. Skutečný sandboxovaný MCP vidí deset nástrojů a přes pracovní bridge vrací notFound pro neexistující requestId, nikoli obecnou chybu spojení.

Existující dokončovací heartbeat byl upraven nástrojem automatizací, se zachováním ID, čísel rozvrhu, hlavního chatu a ACTIVE. Než skončí při nečinném briefingovém workflow, kontroluje i frontu dopracování, zpracuje nejvýše jeden přijatý požadavek a nic nepotvrzuje za člověka. Nová automatizace ani další rutina Aidy nevznikly. [Oficiální dokumentace plánovaných běhů](https://learn.chatgpt.com/docs/automations) vysvětluje dostupnost místního počítače a trvalé instrukce; test této změny neprokazuje budoucí bezobslužný běh.

Miloš doložil skutečné zadání hlavní Aidou: načetla aktuální verzi schůzky, předala porovnání tří variant podle kapacity, rizik a podmínek zahájení a pravdivě oznámila queued. Implementační chat následně zpracoval přesně tento uložený požadavek nad jeho povolenými podklady. Publish ověřil verzi, hash a citaci a uložil completed; skutečný sandboxovaný MCP potvrdil shodu resultVersion s novým detailem a current. Datum je 19. října; zdrojový čas detailu zůstal 18. října 23:11:53 Europe/Prague, nezaměnil se za čas dopracování. Žádné nedoložené počty hodin, rozpočty, lidé ani termíny nebyly vydané za fakt.

Zpětné předání dopracování hlavní Aidou a skutečné dvojkrokové rozhodnutí člověka ještě čekají na potvrzení. Testovací potvrzení do živé evidence agent nevložil. Původní Iris a Mini se neměnily.


## Oprava stalePreparation — 0.5.1

Při prvním živém potvrzení hlavní Aida oznámila stalePreparation. Přímá kontrola potvrdila platnou přihlašovací relaci, podklady staré 31 minut, jeden nepotvrzený návrh a nula recorded rozhodnutí. Původní limit 30 minut se nemění a starý čas podkladu se neopravuje přepisem.

Návrh/potvrzení odmítnuté pro stáří nyní zařadí k obnově jen existující publikovanou úlohu stejného dne. Nevytváří jiný den ani novou práci; do fronty se neukládá lidský souhlas. Při odmítnutí potvrzení se původní návrh zneplatní jako superseded. Ani obsahově shodná obnova neopravňuje znovu použít odmítnutý potvrzovací pokyn: Aida potřebuje nový návrh, skutečné přečtení a nový lidský pokyn.

Worker obnoví již přijatou práci s platnou relací. Pokud přístup chybí, provede pouze prepare a označí awaitingAccess; skutečné upozornění a nové lidské MFA zůstává odděleným protokolem Aidy. Žádný start, noticeSent nebo automatické MFA se tím nepovoluje.

Prošlo 44 syntetických testů jádra a 20 MCP testů. Nové testy ověřují zejména přechod po odmítnutém potvrzení do superseded, obnovení jediné existující úlohy bez změny její identity a zákaz opakování starého souhlasu i po návratu čerstvosti. Samostatně pokrývají čekání na přístup s prepare bez MFA. Worker a MCP host byly obnovené přes stejného správce; nativní Connect zůstal beze změny.

Živá obnova byla zahájená s platnou relací, ale během čtení přístup přestal platit. Nový úplný podklad tím nevznikl. Worker následně správně převedl existující pondělní práci do awaitingAccess; skutečné MCP potvrdilo sessionValid=false, busy=false, workPending=true a phase=awaitingNotice. Nevzniklo přihlášení ani MFA a agent neoznačil upozornění za doručené. Dosavadní dopracování zůstává completed a obnova zálohy prošla. V živé evidenci je pouze nepotvrzený návrh rozhodnutí, nikoli recorded rozhodnutí. Tento první pokus proběhl před aktivací opravy a čeká na běžnou expiraci; neprováděla se přímá úprava jeho stavu za člověka. Po obnově bude nutný nový návrh, readback a nový přímý lidský pokyn. Pozitivní živý rozhodovací průchod zůstává neověřený.
